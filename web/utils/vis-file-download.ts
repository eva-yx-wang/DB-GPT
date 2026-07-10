export interface VisFileDownloadData {
  filename: string;
  media_type: string;
  content_base64: string;
}

function normalizeVisContent(content: string): string {
  return content.replaceAll('\\n', '\n');
}

export function extractVisFileDownload(content: string): VisFileDownloadData | null {
  if (!content || !content.includes('vis-file-download')) {
    return null;
  }

  const normalized = normalizeVisContent(content);

  const fenced = normalized.match(/```vis-file-download\s*\n([\s\S]*?)\n```/);
  if (fenced?.[1]) {
    try {
      return JSON.parse(fenced[1].trim()) as VisFileDownloadData;
    } catch {
      // fall through
    }
  }

  const plain = normalized.match(/vis-file-download\s*\n\s*(\{[\s\S]*\})\s*$/);
  if (plain?.[1]) {
    try {
      return JSON.parse(plain[1].trim()) as VisFileDownloadData;
    } catch {
      // fall through
    }
  }

  return null;
}

export function downloadVisFile(data: VisFileDownloadData): void {
  if (!data?.content_base64) {
    return;
  }

  const binary = atob(data.content_base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }

  const blob = new Blob([bytes], {
    type: data.media_type || 'application/octet-stream',
  });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = data.filename || 'export.csv';
  document.body.appendChild(anchor);
  anchor.click();
  document.body.removeChild(anchor);
  URL.revokeObjectURL(url);
}

export function normalizeChatFlowMessage(message: string): string {
  return normalizeVisContent(message);
}
