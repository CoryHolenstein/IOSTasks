import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  PutCommand,
  QueryCommand,
  DeleteCommand,
  UpdateCommand
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
    taskId: data.taskId ?? `${Date.now()}`
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

function respond(statusCode, body) {
  return { statusCode, headers: HEADERS, body: JSON.stringify(body) };
}

export const handler = async (event) => {
  console.log("EVENT:", event);

  try {
    let body;
    try {
      body = JSON.parse(event.body || "{}");
    } catch {
      throw new HttpError(400, "Request body must be valid JSON");
    }

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
