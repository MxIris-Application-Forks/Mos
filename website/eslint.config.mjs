import nextCoreWebVitals from "eslint-config-next/core-web-vitals";
import typescript from "eslint-config-next/typescript";

const config = [
  ...nextCoreWebVitals,
  ...typescript,
  {
    ignores: [
      "archive/**",
    ],
  },
];

export default config;
