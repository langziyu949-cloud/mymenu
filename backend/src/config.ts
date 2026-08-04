import { z } from 'zod';

const DeepSeekEnvSchema = z.object({
  DEEPSEEK_API_KEY: z.string().min(1),
  DEEPSEEK_BASE_URL: z.string().url().default('https://api.deepseek.com'),
  DEEPSEEK_MODEL: z.enum(['deepseek-v4-flash', 'deepseek-v4-pro'])
    .default('deepseek-v4-flash')
});

const EnvSchema = DeepSeekEnvSchema.extend({
  APP_ACCESS_TOKEN: z.string().min(16),
  PORT: z.coerce.number().int().min(1).max(65535).default(9000)
});

export type DeepSeekConfig = z.infer<typeof DeepSeekEnvSchema>;
export type AppConfig = z.infer<typeof EnvSchema>;

export function loadDeepSeekConfig(env: NodeJS.ProcessEnv = process.env): DeepSeekConfig {
  return DeepSeekEnvSchema.parse(env);
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  return EnvSchema.parse(env);
}
