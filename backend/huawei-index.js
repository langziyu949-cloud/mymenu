'use strict';

let handlerPromise;

exports.handler = async function handler(event) {
  handlerPromise ??= import('./dist/huaweiHandler.js').then((module) => module.handler);
  const runtimeHandler = await handlerPromise;
  return runtimeHandler(event);
};
