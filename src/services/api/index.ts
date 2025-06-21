import { Context, Effect, Layer } from 'effect'
import { api, effectApi, promiseApi } from './client'

/**
 * API Service Tag for dependency injection
 * Provides both Effect-based and Promise-based API clients
 */
export class ApiService extends Context.Tag('ApiService')<
  ApiService,
  {
    effectApi: typeof effectApi
    promiseApi: typeof promiseApi
    rawClient: typeof api
  }
>() {}

/**
 * API Service Layer - provides the API clients
 */
export const ApiServiceLive = Layer.succeed(ApiService, {
  effectApi,
  promiseApi,
  rawClient: api,
})

/**
 * Re-export the API client and types for direct usage
 */
export * from './client'
export { api, effectApi, promiseApi }

/**
 * Effect helper to get the Effect-based API client
 */
export const getEffectApi = Effect.gen(function* () {
  const apiService = yield* ApiService
  return apiService.effectApi
})

/**
 * Effect helper to get the Promise-based API client
 */
export const getPromiseApi = Effect.gen(function* () {
  const apiService = yield* ApiService
  return apiService.promiseApi
})

/**
 * Effect helper to get the raw ofetch client
 */
export const getRawClient = Effect.gen(function* () {
  const apiService = yield* ApiService
  return apiService.rawClient
})
