import js from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["node_modules", "dist"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    rules: {
      // Match the convention tsconfig already enforces: `noUnusedParameters`
      // exempts a leading underscore. Without this, Express's terminal error
      // middleware is unlintable — it is recognised by its arity, so the
      // unused fourth parameter cannot be dropped.
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],
    },
  },
);
