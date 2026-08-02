// A non-lua file, so the text rung has something real to answer about.
// There is no TypeScript grammar on the machines this suite runs on, which
// is the whole point: this is what most of most projects looks like to scry.
import { canonicalUrl } from "./site";

export function renderPrintSheet(checklist: Checklist): string {
  // A mention of loadChecklist that is NOT a definition of it.
  return loadChecklist(checklist.slug);
}

export interface Checklist {
  slug: string;
}

const cache = new Map<string, string>();
