/**
 * Timetable solver worker.
 *
 * Solving is CPU-bound and can run for tens of seconds. Running it on the main
 * thread would freeze the Deputy Rector's browser mid-solve, so it lives here
 * and reports progress back.
 */
import { solve, validate, type SolverInput } from '@edumu/domain'

export type SolveRequest = { type: 'solve'; input: SolverInput }
export type ValidateRequest = { type: 'validate'; input: SolverInput; placements: any[] }
export type WorkerRequest = SolveRequest | ValidateRequest

self.onmessage = (e: MessageEvent<WorkerRequest>) => {
  const msg = e.data
  try {
    if (msg.type === 'solve') {
      const result = solve(msg.input)
      const check = validate(result.placements, msg.input)
      self.postMessage({ type: 'solved', result, check })
    } else {
      self.postMessage({ type: 'validated', check: validate(msg.placements, msg.input) })
    }
  } catch (err) {
    self.postMessage({ type: 'error', message: (err as Error).message })
  }
}
