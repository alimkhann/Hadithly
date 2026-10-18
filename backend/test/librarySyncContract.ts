import type { Validator } from "convex/values";

type WireValidator =
  | { type: "string" | "number" | "boolean" | "null" }
  | { type: "id"; tableName: string }
  | { type: "literal"; value: string | number | boolean | null }
  | { type: "array"; value: WireValidator }
  | { type: "union"; value: WireValidator[] }
  | { type: "object"; value: Record<string, { fieldType: WireValidator; optional: boolean }> };

/** Export only the public validator metadata supported by the native wire generator. */
export function syncValidatorContract(validator: Validator<unknown, "required" | "optional", string>): WireValidator {
  switch (validator.kind) {
    case "string": case "boolean": case "null": return { type: validator.kind };
    case "float64": return { type: "number" };
    case "id": return { type: "id", tableName: validator.tableName };
    case "literal": {
      const value = validator.value;
      if (typeof value === "string" || typeof value === "number" || typeof value === "boolean" || value === null) return { type: "literal", value };
      throw new Error("UNSUPPORTED_SYNC_VALIDATOR");
    }
    case "array": return { type: "array", value: syncValidatorContract(validator.element) };
    case "union": return { type: "union", value: validator.members.map(syncValidatorContract) };
    case "object": return { type: "object", value: Object.fromEntries(Object.entries(validator.fields).map(([key, field]) => [key, { fieldType: syncValidatorContract(field), optional: field.isOptional === "optional" }])) };
    case "any": case "int64": case "bytes": case "record": case "commitTs": throw new Error("UNSUPPORTED_SYNC_VALIDATOR");
    default: { const exhaustive: never = validator; return exhaustive; }
  }
}
