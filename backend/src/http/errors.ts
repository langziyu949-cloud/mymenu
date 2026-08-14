export type PublicErrorCode =
  | 'INVALID_REQUEST'
  | 'UNAUTHORIZED'
  | 'PAYLOAD_TOO_LARGE'
  | 'AI_INVALID_RESPONSE'
  | 'AI_UNAVAILABLE'
  | 'IDENTITY_REQUIRED'
  | 'ACCOUNT_AUTH_UNAVAILABLE'
  | 'INTERNAL_ERROR';

export interface PublicError {
  error: {
    code: PublicErrorCode;
    message: string;
    retryable: boolean;
  };
}

const publicErrors: Record<PublicErrorCode, PublicError['error']> = {
  INVALID_REQUEST: { code: 'INVALID_REQUEST', message: '请求参数无效。', retryable: false },
  UNAUTHORIZED: { code: 'UNAUTHORIZED', message: '未授权访问。', retryable: false },
  PAYLOAD_TOO_LARGE: { code: 'PAYLOAD_TOO_LARGE', message: '请求体过大。', retryable: false },
  AI_INVALID_RESPONSE: { code: 'AI_INVALID_RESPONSE', message: 'AI 返回结果无效。', retryable: false },
  AI_UNAVAILABLE: { code: 'AI_UNAVAILABLE', message: 'AI 服务暂时不可用。', retryable: true },
  IDENTITY_REQUIRED: { code: 'IDENTITY_REQUIRED', message: '华为账号登录已失效，请重新登录。', retryable: false },
  ACCOUNT_AUTH_UNAVAILABLE: {
    code: 'ACCOUNT_AUTH_UNAVAILABLE',
    message: '华为账号认证暂时不可用。',
    retryable: true
  },
  INTERNAL_ERROR: { code: 'INTERNAL_ERROR', message: '服务器内部错误。', retryable: false }
};

export function createPublicError(code: PublicErrorCode): PublicError {
  return { error: publicErrors[code] };
}
