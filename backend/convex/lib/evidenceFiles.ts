import { imageSize } from "image-size";
import { PDFDocument } from "pdf-lib";
import { MAX_EVIDENCE_BYTES } from "./evidencePolicy";

export type VerifiedEvidenceFile = {
  mime: "image/jpeg" | "image/png" | "image/webp" | "application/pdf";
  size: number;
  sha256: string;
  width?: number;
  height?: number;
  pageCount?: number;
};

function detectedMime(bytes: Uint8Array): VerifiedEvidenceFile["mime"] | null {
  if (bytes.length >= 8 && [137, 80, 78, 71, 13, 10, 26, 10].every((byte, i) => bytes[i] === byte)) return "image/png";
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
  if (bytes.length >= 12 && String.fromCharCode(...bytes.slice(0, 4)) === "RIFF" && String.fromCharCode(...bytes.slice(8, 12)) === "WEBP") return "image/webp";
  if (bytes.length >= 5 && String.fromCharCode(...bytes.slice(0, 5)) === "%PDF-") return "application/pdf";
  return null;
}

export async function verifyEvidenceFile(bytes: Uint8Array, declaredMime: string): Promise<VerifiedEvidenceFile> {
  if (bytes.length < 1 || bytes.length > MAX_EVIDENCE_BYTES) throw new Error("Evidence file exceeds the 10 MB limit");
  const mime = detectedMime(bytes);
  if (!mime || mime !== declaredMime) throw new Error("Evidence file type does not match its contents");
  const digestInput = new ArrayBuffer(bytes.length);
  new Uint8Array(digestInput).set(bytes);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", digestInput));
  const sha256 = [...digest].map(byte => byte.toString(16).padStart(2, "0")).join("");
  if (mime === "application/pdf") {
    let pageCount: number;
    try {
      const pdf = await PDFDocument.load(bytes, { updateMetadata: false, ignoreEncryption: false, throwOnInvalidObject: true });
      pageCount = pdf.getPageCount();
    } catch {
      throw new Error("Invalid or encrypted evidence PDF");
    }
    if (pageCount < 1 || pageCount > 25) throw new Error("Evidence PDF must contain 1 to 25 pages");
    return { mime, size: bytes.length, sha256, pageCount };
  }
  let dimensions: ReturnType<typeof imageSize>;
  try { dimensions = imageSize(bytes); } catch { throw new Error("Invalid evidence image"); }
  const { width, height } = dimensions;
  if (!width || !height || width > 12_000 || height > 12_000 || width * height > 40_000_000) throw new Error("Evidence image dimensions exceed the limit");
  if (dimensions.type !== mime.split("/")[1]) throw new Error("Evidence image format does not match its contents");
  return { mime, size: bytes.length, sha256, width, height };
}
