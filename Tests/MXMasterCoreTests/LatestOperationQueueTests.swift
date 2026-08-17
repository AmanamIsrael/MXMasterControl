import Testing

@testable import MXMasterCore

@Test func submitStartsRequestWhenQueueIsIdle() {
  var queue = LatestOperationQueue<Int>()

  let started = queue.submit(7)

  #expect(started)
  #expect(queue.isRunning)
  #expect(queue.current == 7)
  #expect(queue.pending == nil)
}

@Test func submitCoalescesRequestsWhileOneIsRunning() {
  var queue = LatestOperationQueue<Int>()
  _ = queue.submit(1)

  let secondQueued = queue.submit(2)
  #expect(!secondQueued)
  #expect(queue.pending == 2)
  #expect(queue.current == 1)

  let thirdQueued = queue.submit(3)
  #expect(!thirdQueued)
  #expect(queue.pending == 3)
  #expect(queue.current == 1)
}

@Test func finishCurrentRunsQueuedRequestAndKeepsQueueRunning() {
  var queue = LatestOperationQueue<Int>()
  _ = queue.submit(1)
  _ = queue.submit(2)

  let next = queue.finishCurrent()

  #expect(next == 2)
  #expect(queue.isRunning)
  #expect(queue.current == 2)
  #expect(queue.pending == nil)
}

@Test func finishCurrentIdlesQueueWhenNoRequestIsQueued() {
  var queue = LatestOperationQueue<Int>()
  _ = queue.submit(1)

  let next = queue.finishCurrent()

  #expect(next == nil)
  #expect(!queue.isRunning)
  #expect(queue.current == nil)
}

@Test func abandonDiscardsCurrentAndQueuedRequests() {
  var queue = LatestOperationQueue<Int>()
  _ = queue.submit(1)
  _ = queue.submit(2)

  queue.abandon()

  #expect(!queue.isRunning)
  #expect(queue.current == nil)
  #expect(queue.pending == nil)
}

@Test func queueAcceptsNewRequestAfterAbandon() {
  var queue = LatestOperationQueue<Int>()
  _ = queue.submit(1)
  queue.abandon()

  let started = queue.submit(4)

  #expect(started)
  #expect(queue.current == 4)
  #expect(queue.isRunning)
}