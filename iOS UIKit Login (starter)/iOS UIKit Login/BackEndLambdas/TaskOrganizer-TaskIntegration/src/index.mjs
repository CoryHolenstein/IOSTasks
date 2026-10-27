import { randomUUID } from "node:crypto";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  PutCommand,
  QueryCommand,
  DeleteCommand,
  UpdateCommand,
  BatchWriteCommand
} from "@aws-sdk/lib-dynamodb";

// The Document client converts plain JS objects to/from DynamoDB's format.
// removeUndefinedValues: skip fields the app didn't send instead of throwing.
const client = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true }
});
const TABLE_NAME = "tasks";

const HEADERS = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "http://localhost:5173",
  "Access-Control-Allow-Headers": "content-type,authorization,x-requested-with,accept,origin",
  "Access-Control-Allow-Methods": "OPTIONS,POST"
};

// Every field the app may set on a task (everything except the keys userId + taskId).
const TASK_FIELDS = [
  "name",
  "description",
  "dueDate",               // "YYYY-MM-DD" or ""
  "dueTime",               // "HH:mm" or ""
  "repeat",                // "never", "daily", "every 4 hours"... (kept for older tasks)
  "recurrence",            // { interval: 4, unit: "hour" } or null
  "importance",            // "none" | "low" | "medium" | "high"
  "reminderMinutesBefore", // 0, 5, 15, 30, 60, 1440 or null
  "alertStyle"             // "quiet" | "standard" | "urgent"
];

/**
 * The signed-in user's ID, taken from the verified Auth0 token.
 * API Gateway's JWT authorizer checks the token's signature, issuer, audience
 * and expiry before this Lambda runs, and passes the token's claims along.
 * "sub" is the user's permanent Auth0 ID, e.g. "auth0|65f0c1...".
 * We never trust a userId sent in the request body.
 */
function getUserId(event) {
  const sub = event.requestContext?.authorizer?.jwt?.claims?.sub;
  if (!sub) {
    throw new HttpError(401, "Not signed in");
  }
  return sub;
}

class HttpError extends Error {
  constructor(statusCode, message) {
    super(message);
    this.statusCode = statusCode;
  }
}

function requireFields(data, fields) {
  for (const field of fields) {
    const value = data[field];
    if (value === undefined || value === null || value === "") {
      throw new HttpError(400, `Missing required field: ${field}`);
    }
  }
}

/** Copies only the known task fields that were actually sent. */
function pickTaskFields(data) {
  const fields = {};
  for (const key of TASK_FIELDS) {
    if (data[key] !== undefined) {
      fields[key] = data[key];
    }
  }
  return fields;
}

async function createTask(data) {
  requireFields(data, ["userId", "name"]);

  const fields = pickTaskFields(data);
  // null means "not set", so don't store it on a new task
  for (const key of Object.keys(fields)) {
    if (fields[key] === null) delete fields[key];
  }

  const item = {
    ...fields,
    userId: data.userId,
    // Random ID: timestamps can collide when two tasks are created in the same millisecond
    taskId: data.taskId ?? randomUUID()
  };

  try {
    await client.send(new PutCommand({
      TableName: TABLE_NAME,
      Item: item,
      // Never silently overwrite an existing task; that's what edit-task is for.
      ConditionExpression: "attribute_not_exists(taskId)"
    }));
  } catch (err) {
    if (err.name === "ConditionalCheckFailedException") {
      throw new HttpError(409, "A task with this ID already exists");
    }
    throw err;
  }

  return { message: "Task created", item };
}

async function getAllTasks(data) {
  requireFields(data, ["userId"]);

  const result = await client.send(new QueryCommand({
    TableName: TABLE_NAME,
    KeyConditionExpression: "userId = :u",
    ExpressionAttributeValues: { ":u": data.userId }
  }));

  return { tasks: result.Items || [] };
}

/**
 * Updates only the fields that were sent.
 * A field sent as null is removed from the task (e.g. turning off "Repeat").
 */
async function editTask(data) {
  requireFields(data, ["userId", "taskId"]);

  const fields = pickTaskFields(data);
  if ("name" in fields && (typeof fields.name !== "string" || fields.name.trim() === "")) {
    throw new HttpError(400, "Task name can't be empty");
  }

  // Placeholders (#f0, :v0...) avoid clashes with DynamoDB reserved words like "name".
  const names = { "#taskId": "taskId" };
  const values = {};
  const setParts = [];
  const removeParts = [];

  Object.entries(fields).forEach(([key, value], index) => {
    names[`#f${index}`] = key;
    if (value === null) {
      removeParts.push(`#f${index}`);
    } else {
      values[`:v${index}`] = value;
      setParts.push(`#f${index} = :v${index}`);
    }
  });

  if (setParts.length === 0 && removeParts.length === 0) {
    throw new HttpError(400, "Nothing to update");
  }

  const expressionParts = [];
  if (setParts.length > 0) expressionParts.push(`SET ${setParts.join(", ")}`);
  if (removeParts.length > 0) expressionParts.push(`REMOVE ${removeParts.join(", ")}`);

  const params = {
    TableName: TABLE_NAME,
    Key: { userId: data.userId, taskId: data.taskId },
    UpdateExpression: expressionParts.join(" "),
    // Only edit tasks that exist; don't create a half-empty one by accident.
    ConditionExpression: "attribute_exists(#taskId)",
    ExpressionAttributeNames: names,
    ReturnValues: "ALL_NEW"
  };
  if (setParts.length > 0) {
    params.ExpressionAttributeValues = values;
  }

  try {
    const result = await client.send(new UpdateCommand(params));
    return { message: "Task updated", item: result.Attributes };
  } catch (err) {
    if (err.name === "ConditionalCheckFailedException") {
      throw new HttpError(404, "Task not found");
    }
    throw err;
  }
}

async function deleteTask(data) {
  requireFields(data, ["userId", "taskId"]);

  await client.send(new DeleteCommand({
    TableName: TABLE_NAME,
    Key: { userId: data.userId, taskId: data.taskId }
  }));

  return { message: "Task deleted" };
}

// ---------------------------------------------------------------------------
// Account deletion (required by the App Store)
// Needs these environment variables on the Lambda (Configuration → Environment variables):
//   AUTH0_DOMAIN               e.g. dev-xxxx.us.auth0.com
//   AUTH0_MGMT_CLIENT_ID       from a Machine-to-Machine app in Auth0
//   AUTH0_MGMT_CLIENT_SECRET   allowed to call the Auth0 Management API with "delete:users"
// ---------------------------------------------------------------------------

let managementToken = null; // { value, expiresAt } reused while the Lambda stays warm

async function getManagementToken() {
  if (managementToken && managementToken.expiresAt > Date.now() + 60_000) {
    return managementToken.value;
  }

  const { AUTH0_DOMAIN, AUTH0_MGMT_CLIENT_ID, AUTH0_MGMT_CLIENT_SECRET } = process.env;
  if (!AUTH0_DOMAIN || !AUTH0_MGMT_CLIENT_ID || !AUTH0_MGMT_CLIENT_SECRET) {
    throw new HttpError(500, "Account deletion isn't set up on the server yet");
  }

  const response = await fetch(`https://${AUTH0_DOMAIN}/oauth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      grant_type: "client_credentials",
      client_id: AUTH0_MGMT_CLIENT_ID,
      client_secret: AUTH0_MGMT_CLIENT_SECRET,
      audience: `https://${AUTH0_DOMAIN}/api/v2/`
    })
  });

  if (!response.ok) {
    console.error("Auth0 token request failed:", response.status, await response.text());
    throw new HttpError(502, "Couldn't reach the login service. Please try again.");
  }

  const json = await response.json();
  managementToken = {
    value: json.access_token,
    expiresAt: Date.now() + (json.expires_in ?? 3600) * 1000
  };
  return managementToken.value;
}

/** Deletes the user's login from Auth0. Safe to repeat. */
async function deleteAuth0User(userId) {
  const token = await getManagementToken();
  const response = await fetch(
    `https://${process.env.AUTH0_DOMAIN}/api/v2/users/${encodeURIComponent(userId)}`,
    { method: "DELETE", headers: { Authorization: `Bearer ${token}` } }
  );

  // 204 = deleted, 404 = already gone
  if (!response.ok && response.status !== 404) {
    console.error("Auth0 user delete failed:", response.status, await response.text());
    throw new HttpError(502, "Your tasks were deleted, but your login couldn't be removed. Please try again.");
  }
}

/** Deletes every task the user owns, 25 at a time. Returns how many were deleted. */
async function deleteAllTasks(userId) {
  let deleted = 0;
  let lastKey;

  do {
    const page = await client.send(new QueryCommand({
      TableName: TABLE_NAME,
      KeyConditionExpression: "userId = :u",
      ExpressionAttributeValues: { ":u": userId },
      ProjectionExpression: "userId, taskId",
      ExclusiveStartKey: lastKey
    }));

    const keys = (page.Items || []).map((item) => ({ userId: item.userId, taskId: item.taskId }));

    for (let start = 0; start < keys.length; start += 25) {
      const batch = keys.slice(start, start + 25);
      let pending = batch.map((Key) => ({ DeleteRequest: { Key } }));

      // DynamoDB can hand back items it didn't get to; retry those with a short backoff.
      for (let attempt = 0; pending.length > 0 && attempt < 5; attempt++) {
        if (attempt > 0) {
          await new Promise((resolve) => setTimeout(resolve, 100 * 2 ** attempt));
        }
        const result = await client.send(new BatchWriteCommand({
          RequestItems: { [TABLE_NAME]: pending }
        }));
        pending = result.UnprocessedItems?.[TABLE_NAME] ?? [];
      }

      if (pending.length > 0) {
        throw new HttpError(503, "Couldn't delete all of your tasks. Please try again.");
      }
      deleted += batch.length;
    }

    lastKey = page.LastEvaluatedKey;
  } while (lastKey);

  return deleted;
}

async function deleteAccount(data) {
  requireFields(data, ["userId"]);

  // Make sure we can reach Auth0 before deleting anything, so a setup problem
  // (missing environment variables, wrong credentials) leaves everything as it was.
  await getManagementToken();

  // Tasks next: if removing the login then fails, trying again still works.
  const deletedTasks = await deleteAllTasks(data.userId);
  await deleteAuth0User(data.userId);

  return { message: "Account deleted", deletedTasks };
}

function respond(statusCode, body) {
  return { statusCode, headers: HEADERS, body: JSON.stringify(body) };
}

export const handler = async (event) => {
  // Log the route only; the full event contains the user's token.
  console.log("REQUEST:", event.rawPath);

  try {
    let body;
    try {
      body = JSON.parse(event.body || "{}");
    } catch {
      throw new HttpError(400, "Request body must be valid JSON");
    }
    if (body === null || typeof body !== "object" || Array.isArray(body)) {
      throw new HttpError(400, "Request body must be a JSON object");
    }

    // Always act as the signed-in user, whatever userId the body claims.
    body.userId = getUserId(event);

    const path = event.rawPath || "";
    let result;

    if (path.endsWith("/tasks/create-task")) {
      result = await createTask(body);
    } else if (path.endsWith("/tasks/get-all-tasks")) {
      result = await getAllTasks(body);
    } else if (path.endsWith("/tasks/edit-task")) {
      result = await editTask(body);
    } else if (path.endsWith("/tasks/delete-task")) {
      result = await deleteTask(body);
    } else if (path.endsWith("/tasks/delete-account")) {
      result = await deleteAccount(body);
    } else {
      throw new HttpError(400, "Unknown route");
    }

    return respond(200, result);

  } catch (err) {
    console.error("ERROR:", err);
    const statusCode = err.statusCode ?? 500;
    return respond(statusCode, { error: err.message });
  }
};
