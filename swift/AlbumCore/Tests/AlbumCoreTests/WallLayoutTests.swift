import Testing

@testable import AlbumCore

@Suite struct WallLayoutTests {
  @Test func narrowScreensUseFixedColumnsPerDensity() {
    #expect(WallLayout.metrics(width: 375, density: .compact).columns == 3)
    #expect(WallLayout.metrics(width: 375, density: .standard).columns == 2)
    #expect(WallLayout.metrics(width: 375, density: .roomy).columns == 1)
  }

  @Test func wideScreensUseTargetWidthWithAtLeastTwoColumns() {
    #expect(WallLayout.metrics(width: 1136, density: .standard).columns == 5)
    #expect(WallLayout.metrics(width: 620, density: .roomy).columns == 2)
  }

  @Test func columnsAndGapsFillTheContainer() {
    let m = WallLayout.metrics(width: 1136, density: .standard)
    let total = m.columnWidth * Double(m.columns) + m.gap * Double(m.columns - 1)
    #expect(abs(total - 1136) < 0.0001)
  }

  @Test func ordinaryRatiosAreKept() {
    #expect(WallLayout.displayRatio(width: 2000, height: 3000) == .init(ratio: 1.5, long: false, cropped: false))
  }

  @Test func longImagesAreCappedAndMarked() {
    let r = WallLayout.displayRatio(width: 1000, height: 5000)
    #expect(r.ratio == WallLayout.maxRatio)
    #expect(r.long)
    #expect(r.cropped)
  }

  @Test func wideImagesAreCappedButNotLong() {
    let r = WallLayout.displayRatio(width: 3000, height: 1000)
    #expect(r.ratio == WallLayout.minRatio)
    #expect(!r.long)
    #expect(r.cropped)
  }

  let metrics = WallLayout.Metrics(columns: 2, gap: 10, footer: 20, columnWidth: 100)

  @Test func tilesGoToTheShortestColumnLeftOnTies() {
    let (placements, heights) = WallLayout.placeTiles([1, 2, 1], metrics: metrics)
    #expect(placements.map { [$0.x, $0.y] } == [[0, 0], [110, 0], [0, 130]])
    #expect(placements[1].height == 220)
    #expect(heights == [260, 230])
  }

  @Test func placementCanContinueFromExistingHeights() {
    let (placements, _) = WallLayout.placeTiles([1], metrics: metrics, start: [300, 50])
    #expect(placements[0].x == 110)
    #expect(placements[0].y == 50)
  }

  @Test func mediaHeightRoundsLikeJavaScript() {
    let m = WallLayout.Metrics(columns: 1, gap: 0, footer: 0, columnWidth: 101)
    // 101 × 1.5 = 151.5 → Math.round 得 152
    #expect(WallLayout.placeTiles([1.5], metrics: m).placements[0].mediaHeight == 152)
  }

  let keys = ["a", "b", "c", "d", "e", "f"]

  @Test func readyTilesInTheWindowArePlacedFirst() {
    let ready: Set = [1, 2]
    #expect(WallLayout.extendPlacement([], keys: keys, isReady: { ready.contains($0) }, windowSize: 4) == ["b", "c"])
  }

  @Test func placementDoesNotSkipPastTheWindow() {
    let ready: Set = [4, 5]
    #expect(WallLayout.extendPlacement([], keys: keys, isReady: { ready.contains($0) }, windowSize: 4) == nil)
  }

  @Test func slowTileJoinsAfterThePlacedOnes() {
    let next = WallLayout.extendPlacement(["b", "c"], keys: keys, isReady: { $0 <= 3 }, windowSize: 4)
    #expect(next == ["b", "c", "a", "d"])
  }

  @Test func nothingNewReturnsNil() {
    #expect(WallLayout.extendPlacement(["a"], keys: keys, isReady: { _ in false }, windowSize: 4) == nil)
  }
}
