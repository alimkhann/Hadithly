export const FOLDER_NAME_LIMIT = 64;
export const FOLDER_EFFECT_PAGE = 4;
export const FOLDER_HANDLE_RETENTION_MS = 30 * 24 * 60 * 60_000;
export const FOLDER_WORK_LEASE_MS = 30 * 60_000;

export function normalizedFolderName(name: string): { name: string; normalizedName: string } {
  const displayName = name.trim().normalize("NFC");
  if (!displayName) throw new Error("FOLDER_NAME_EMPTY");
  if (/\p{Cc}/u.test(displayName)) throw new Error("FOLDER_NAME_CONTROL_CHARACTER");
  if (Array.from(displayName).length > FOLDER_NAME_LIMIT) {
    throw new Error("FOLDER_NAME_TOO_LONG");
  }
  return { name: displayName, normalizedName: displayName.toLocaleLowerCase() };
}
