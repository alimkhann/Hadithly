function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

/** Only pass the authenticated Google decode response here, never client verdicts. */
export function validPlayIntegrity(value: unknown, expected: { packageName: string; requestHash: string; certificateDigests: string[]; now: number }): boolean {
  if (!record(value) || !record(value.tokenPayloadExternal)) return false;
  const payload = value.tokenPayloadExternal;
  const request = payload.requestDetails, app = payload.appIntegrity, device = payload.deviceIntegrity, account = payload.accountDetails;
  if (!record(request) || !record(app) || !record(device) || !record(account)) return false;
  const timestamp = typeof request.timestampMillis === "string" ? Number(request.timestampMillis) : NaN;
  return request.requestPackageName === expected.packageName && request.requestHash === expected.requestHash &&
    Number.isSafeInteger(timestamp) && timestamp <= expected.now + 5_000 && timestamp > expected.now - 120_000 &&
    app.appRecognitionVerdict === "PLAY_RECOGNIZED" && app.packageName === expected.packageName &&
    Array.isArray(app.certificateSha256Digest) && app.certificateSha256Digest.some(digest => typeof digest === "string" && expected.certificateDigests.includes(digest)) &&
    Array.isArray(device.deviceRecognitionVerdict) && device.deviceRecognitionVerdict.includes("MEETS_DEVICE_INTEGRITY") &&
    account.appLicensingVerdict === "LICENSED";
}
