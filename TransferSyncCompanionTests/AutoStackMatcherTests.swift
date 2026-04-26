import XCTest
@testable import TransferSyncCompanion

final class AutoStackMatcherTests: XCTestCase {

 // MARK: - findBestMatch

 func testFindBestMatch_exactNameDifferentExtension() {
 let candidates = [
 FolderAsset(id: "a1", name: "drums-take-01.wav", assetType: "file"),
 FolderAsset(id: "a2", name: "vocals-chorus.wav", assetType: "file"),
 ]

 let match = AutoStackMatcher.findBestMatch(fileName: "drums-take-02.wav", candidates: candidates)
 XCTAssertNotNil(match)
 XCTAssertEqual(match?.assetId, "a1")
 }

 func testFindBestMatch_prefersStack() {
 let candidates = [
 FolderAsset(id: "file1", name: "main-vocal-take.wav", assetType: "file"),
 FolderAsset(id: "stack1", name: "main-vocal-take", assetType: "stack"),
 ]

 let match = AutoStackMatcher.findBestMatch(fileName: "main-vocal-take-02.wav", candidates: candidates)
 XCTAssertNotNil(match)
 // Stack should be preferred due to 0.25 bonus
 XCTAssertEqual(match?.assetId, "stack1")
 }

 func testFindBestMatch_noMatchForUnrelatedFile() {
 let candidates = [
 FolderAsset(id: "a1", name: "drums-take-01.wav", assetType: "file"),
 ]

 let match = AutoStackMatcher.findBestMatch(fileName: "completely-different-song.wav", candidates: candidates)
 XCTAssertNil(match)
 }

 func testFindBestMatch_emptyFileName() {
 let candidates = [
 FolderAsset(id: "a1", name: "drums.wav", assetType: "file"),
 ]

 let match = AutoStackMatcher.findBestMatch(fileName: ".wav", candidates: candidates)
 XCTAssertNil(match)
 }

 func testFindBestMatch_emptyCandidates() {
 let match = AutoStackMatcher.findBestMatch(fileName: "drums.wav", candidates: [])
 XCTAssertNil(match)
 }

 func testFindBestMatch_candidateWithNilName() {
 let candidates = [
 FolderAsset(id: "a1", name: nil, assetType: "file"),
 ]

 let match = AutoStackMatcher.findBestMatch(fileName: "drums.wav", candidates: candidates)
 XCTAssertNil(match)
 }

 func testFindBestMatch_caseInsensitive() {
 let candidates = [
 FolderAsset(id: "a1", name: "Drums-Take-01.wav", assetType: "file"),
 ]

 let match = AutoStackMatcher.findBestMatch(fileName: "drums-take-02.wav", candidates: candidates)
 XCTAssertNotNil(match)
 XCTAssertEqual(match?.assetId, "a1")
 }

 func testFindBestMatch_underscoreSeparator() {
 let candidates = [
 FolderAsset(id: "a1", name: "lead_vocal_take_1.wav", assetType: "file"),
 ]

 let match = AutoStackMatcher.findBestMatch(fileName: "lead_vocal_take_2.wav", candidates: candidates)
 XCTAssertNotNil(match)
 XCTAssertEqual(match?.assetId, "a1")
 }

 func testFindBestMatch_spaceSeparator() {
 let candidates = [
 FolderAsset(id: "a1", name: "lead vocal take 1.wav", assetType: "file"),
 ]

 let match = AutoStackMatcher.findBestMatch(fileName: "lead vocal take 2.wav", candidates: candidates)
 XCTAssertNotNil(match)
 XCTAssertEqual(match?.assetId, "a1")
 }

 func testFindBestMatch_numericOnlyTokensIgnored() {
 // Pure numeric file names should not match - meaningful tokens needed
 let candidates = [
 FolderAsset(id: "a1", name: "123.wav", assetType: "file"),
 ]

 let match = AutoStackMatcher.findBestMatch(fileName: "456.wav", candidates: candidates)
 XCTAssertNil(match, "Purely numeric names should not match")
 }

 func testFindBestMatch_selectsBestAmongMultiple() {
 let candidates = [
 FolderAsset(id: "a1", name: "guitar-solo-take-1.wav", assetType: "file"),
 FolderAsset(id: "a2", name: "guitar-rhythm-take-1.wav", assetType: "file"),
 FolderAsset(id: "a3", name: "bass-line-take-1.wav", assetType: "file"),
 ]

 let match = AutoStackMatcher.findBestMatch(fileName: "guitar-solo-take-2.wav", candidates: candidates)
 XCTAssertNotNil(match)
 XCTAssertEqual(match?.assetId, "a1", "Should match the candidate with the longest common word sequence")
 }

 func testFindBestMatch_coverageThreshold() {
 // "hello" vs "hello world universe galaxy" - 1/4 coverage = 25% < 50% threshold
 let candidates = [
 FolderAsset(id: "a1", name: "hello world universe galaxy.wav", assetType: "file"),
 ]

 let match = AutoStackMatcher.findBestMatch(fileName: "hello.wav", candidates: candidates)
 // Coverage from shorter side: 1/1 = 100% (shorter = "hello" with 1 meaningful word)
 // This should still match because coverage is based on shorter meaningful count
 XCTAssertNotNil(match)
 }

 // MARK: - S3 Key Construction

 func testRawS3Key() {
 let key = S3UploadService.rawS3Key(mediaId: "abc-123", fileName: "vocals.wav")
 XCTAssertEqual(key, "assets/abc-123/abc-123.wav")
 }

 func testRawS3Key_noExtension() {
 let key = S3UploadService.rawS3Key(mediaId: "abc-123", fileName: "noext")
 XCTAssertEqual(key, "assets/abc-123/abc-123")
 }

 func testRawS3Key_uppercaseExtension() {
 let key = S3UploadService.rawS3Key(mediaId: "abc-123", fileName: "Track.FLAC")
 XCTAssertEqual(key, "assets/abc-123/abc-123.flac")
 }
}
