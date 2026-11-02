// The bundled faces (DESIGN.md 4): never fetched from anywhere but the extension.
// `base` is where the font files are: '../fonts/' from an extension page,
// chrome.runtime.getURL('fonts/') from a content script.

const faces: [family: string, file: string, weight: number, style: string][] = [
  ['Fraunces', 'Fraunces-Regular.ttf', 400, 'normal'],
  ['Fraunces', 'Fraunces-SemiBold.ttf', 600, 'normal'],
  ['Fraunces', 'Fraunces-Italic.ttf', 400, 'italic'],
  ['Fraunces Display', 'FrauncesDisplay-SemiBold.ttf', 600, 'normal'],
  ['Public Sans', 'PublicSans-Regular.ttf', 400, 'normal'],
  ['Public Sans', 'PublicSans-Medium.ttf', 500, 'normal'],
  ['Public Sans', 'PublicSans-SemiBold.ttf', 600, 'normal'],
];

export const fontFaces = (base: string) =>
  faces
    .map(
      ([family, file, weight, style]) =>
        `@font-face{font-family:'${family}';src:url('${base}${file}') format('truetype');font-weight:${weight};font-style:${style};font-display:swap}`,
    )
    .join('\n');
