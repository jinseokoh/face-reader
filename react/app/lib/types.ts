export type ShareCardKind = "physiognomy" | "compat";

export interface Highlight {
  title: string;
  detail: string;
}

export interface ShareCardData {
  shortId: string;
  kind: ShareCardKind;
  cardImageUrl: string;
  label: string;
  totalScore: number;
  tagline: string;
  highlights: Highlight[];
  ogTitle: string;
  ogDescription: string;
  ogImage: string;
  expiresAt: string | null;
  appLinkBase: string;
  appStoreUrl: string;
  playStoreUrl: string;
}
