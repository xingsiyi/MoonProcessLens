///|
struct Stamped {
  event : Event
  ordinal : Int64
}

///|
fn before(left : Stamped, right : Stamped) -> Bool {
  left.event.time < right.event.time ||
  (left.event.time == right.event.time && left.ordinal < right.ordinal)
}

///|
fn heap_push(heap : Array[Stamped], item : Stamped) -> Unit {
  heap.push(item)
  let mut index = heap.length() - 1
  while index > 0 {
    let parent = (index - 1) / 2
    if !before(heap[index], heap[parent]) {
      break
    }
    let saved = heap[parent]
    heap[parent] = heap[index]
    heap[index] = saved
    index = parent
  }
}

///|
fn heap_pop(heap : Array[Stamped]) -> Stamped? {
  if heap.is_empty() {
    return None
  }
  let first = heap[0]
  let last = heap.pop().unwrap()
  if !heap.is_empty() {
    heap[0] = last
    let mut index = 0
    while index * 2 + 1 < heap.length() {
      let left = index * 2 + 1
      let right = left + 1
      let smallest = if right < heap.length() && before(heap[right], heap[left]) {
        right
      } else {
        left
      }
      if !before(heap[smallest], heap[index]) {
        break
      }
      let saved = heap[index]
      heap[index] = heap[smallest]
      heap[smallest] = saved
      index = smallest
    }
  }
  Some(first)
}
