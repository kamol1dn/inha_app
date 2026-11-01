// HTML and XML parsing for the service parsers. Extension pages and content
// scripts have the browser's DOMParser; the service worker and the Node tests
// get linkedom's, installed on globalThis by src/background/dom-shim.ts and
// test/setup.ts. Parsers only use what both implement: querySelector(All),
// textContent, attributes, children, localName, classList.

export function parseHtml(html: string): Document {
  return new DOMParser().parseFromString(html, 'text/html');
}

export function parseXml(xml: string): Document {
  return new DOMParser().parseFromString(xml, 'text/xml');
}

/** Element text with whitespace (including &nbsp;) collapsed. */
export function text(e: Element | null | undefined): string {
  return e ? (e.textContent ?? '').replace(/ /g, ' ').replace(/\s+/g, ' ').trim() : '';
}

/** An integer query parameter of a (possibly relative) href. */
export function intParam(href: string | null | undefined, name: string): number | null {
  if (!href) return null;
  try {
    const v = new URL(href.trim(), 'https://x.invalid/').searchParams.get(name);
    if (v == null || !/^-?\d+$/.test(v)) return null;
    return Number(v);
  } catch {
    return null;
  }
}

/** Elements under `root` with the given local name, matched without namespaces (EWS SOAP). */
export function byTag(root: Document | Element, localName: string): Element[] {
  return Array.from(root.getElementsByTagName('*')).filter((e) => e.localName === localName);
}

export function firstTag(root: Document | Element, localName: string): Element | null {
  return byTag(root, localName)[0] ?? null;
}
