/**
 * Timetable solver benchmark against a realistic Mauritian secondary school.
 *
 *   node --experimental-strip-types scripts/bench-timetable.ts
 *
 * Reference results on a 24-class / 192-set school (≈870 pupils, 45 educators,
 * 31 rooms, 990 conflict edges, 696 periods to place into 40 slots):
 *
 *   construction only   47 ms   696/696 placed, 0 hard violations
 *   + 20 s local search         696/696 placed, 0 hard violations, ~660k iterations
 *
 * The blueprint's NFR asks for a first viable solution in under 2 minutes.
 */
import { solve, validate, buildConflictGraph } from '../packages/domain/src/timetable.ts'

const CLASSES = Number(process.env.CLASSES ?? 24)
const BUDGET = Number(process.env.BUDGET_MS ?? 20000)

const rooms: any[] = []
for (let i = 1; i <= 26; i++) rooms.push({ id: `r${i}`, code: `R${i}`, roomType: 'classroom', capacity: 40 })
for (let i = 1; i <= 3; i++)  rooms.push({ id: `lab${i}`, code: `LAB${i}`, roomType: 'science_lab', capacity: 32 })
for (let i = 1; i <= 2; i++)  rooms.push({ id: `it${i}`, code: `IT${i}`, roomType: 'computer_room', capacity: 30 })

const subjects: [string, string | null][] = [
  ['MATH', null], ['ENG', null], ['FRE', null], ['HIST', null],
  ['GEOG', null], ['BIO', 'science_lab'], ['CHEM', 'science_lab'], ['CS', 'computer_room'],
]

const sets: any[] = []
const educators: any[] = []
const N_EDUCATORS = 45
for (let i = 0; i < N_EDUCATORS; i++) educators.push({ id: `e${i}`, unavailable: [] })

let ei = 0
for (let c = 1; c <= CLASSES; c++) {
  const pupils = Array.from({ length: 36 }, (_, i) => `c${c}s${i}`)
  for (const [code, rt] of subjects) {
    sets.push({
      id: `${code}-${c}`, name: `C${c} ${code}`,
      periodsPerCycle: rt ? 3 : 4, doublePeriods: 0,
      educatorIds: [`e${ei++ % N_EDUCATORS}`], studentIds: pupils,
      requiredRoomType: rt, preferredRoomId: null, size: 36,
    })
  }
}

const input = { cycleLength: 5, periods: [1,2,3,4,5,6,7,8], rooms, educators, sets, seed: 5, timeBudgetMs: BUDGET }

const graph = buildConflictGraph(sets)
let edges = 0
for (const [, s] of graph) edges += s.size
const required = sets.reduce((n, s) => n + s.periodsPerCycle, 0)

console.log(`classes=${CLASSES} sets=${sets.length} educators=${N_EDUCATORS} rooms=${rooms.length}`)
console.log(`conflict-edges=${edges / 2} periods=${required} slots=${5 * 8}`)

const t0 = Date.now()
const r = solve(input as any)
console.log(`solved in ${Date.now() - t0}ms, ${r.iterations} local-search iterations`)
console.log(`placed=${r.placements.length}/${required} unplaced=${r.unplaced.length} score=${r.score.toFixed(0)}`)
if (r.unplaced.length) console.log('unplaced examples:', r.unplaced.slice(0, 4))

const v = validate(r.placements, input as any)
console.log(`hard constraints satisfied: ${v.ok}`)
if (!v.ok) { console.log(v.problems.slice(0, 5)); process.exit(1) }
