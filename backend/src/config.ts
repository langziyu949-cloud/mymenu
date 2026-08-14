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

const HuaweiAccountEnvSchema = z.object({
  HUAWEI_ACCOUNT_CLIENT_ID: z.string().regex(/^\d{1,64}$/),
  HUAWEI_ACCOUNT_CLIENT_SECRET: z.string().min(1),
  IDENTITY_SESSION_SECRET: z.string().min(32)
});

export type DeepSeekConfig = z.infer<typeof DeepSeekEnvSchema>;
export type AppConfig = z.infer<typeof EnvSchema>;
export type HuaweiAccountConfig = z.infer<typeof HuaweiAccountEnvSchema>;

export function loadDeepSeekConfig(env: NodeJS.ProcessEnv = process.env): DeepSeekConfig {
  return DeepSeekEnvSchema.parse(env);
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  return EnvSchema.parse(env);
}

export function loadHuaweiAccountConfig(env: NodeJS.ProcessEnv = process.env): HuaweiAccountConfig {
  return HuaweiAccountEnvSchema.parse(env);
}
