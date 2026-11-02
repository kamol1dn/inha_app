// esbuild imports .css files as text (loader 'text' in build.mjs).
declare module '*.css' {
  const css: string;
  export default css;
}
