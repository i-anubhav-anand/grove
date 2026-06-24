import Foundation
import WorktreeKit

// POC-1: Prove the worktree primitive end to end.
//
// Simulates the core move: two agents working the SAME repo on TWO
// branches in parallel, fully isolated. Creates a throwaway repo so the run is
// self-contained — no external setup needed.

func sh(_ cmd: String, cwd: String? = nil) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
    p.arguments = ["-c", cmd]
    if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
    try p.run()
    p.waitUntilExit()
    if p.terminationStatus != 0 { throw NSError(domain: "sh", code: Int(p.terminationStatus)) }
}

final class Result: @unchecked Sendable { var code: Int32 = 0 }
let result = Result()

func check(_ label: String, _ condition: Bool) {
    print(condition ? "  ✅ \(label)" : "  ❌ \(label)")
    if !condition { result.code = 1 }
}

let tmp = FileManager.default.temporaryDirectory
    .appendingPathComponent("wtpoc-\(UUID().uuidString.prefix(8))", isDirectory: true)
let repo = tmp.appendingPathComponent("repo", isDirectory: true)
let base = tmp.appendingPathComponent("worktrees", isDirectory: true)

do {
    // --- Set up a throwaway repo with one commit ---
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    try sh("git init -q && git config user.email t@t.co && git config user.name t && echo hello > README.md && git add -A && git commit -qm init", cwd: repo.path)
    print("\n📦 Throwaway repo at \(repo.path)\n")

    let svc = GitWorktreeService(baseDir: base)

    // --- Two agents, two branches, same repo, in parallel ---
    print("Creating two isolated worktrees (agent-a, agent-b)…")
    async let pathA = svc.createWorktree(repo: repo.path, branch: "agent-a")
    async let pathB = svc.createWorktree(repo: repo.path, branch: "agent-b")
    let (a, b) = try await (pathA, pathB)
    print("  agent-a → \(a)")
    print("  agent-b → \(b)\n")

    check("two distinct worktree paths", a != b)
    check("agent-a dir exists", FileManager.default.fileExists(atPath: a))
    check("agent-b dir exists", FileManager.default.fileExists(atPath: b))

    // --- Prove isolation: a file written in A is invisible in B ---
    try sh("echo 'agent A was here' > only_in_a.txt", cwd: a)
    check("file in A is NOT visible in B (isolated)",
          !FileManager.default.fileExists(atPath: b + "/only_in_a.txt"))

    // --- Prove they're on different branches ---
    let list = try await svc.listWorktrees(repo: repo.path)
    let branches = Set(list.compactMap { $0.branch })
    print("\nWorktrees registered with git:")
    for w in list { print("  • \(w.branch ?? "(detached)")  @ \(w.head.prefix(8))  \(w.path)") }
    check("git sees agent-a branch", branches.contains("agent-a"))
    check("git sees agent-b branch", branches.contains("agent-b"))
    check("main + 2 worktrees = 3 total", list.count == 3)

    // --- Cleanup (the "archive" path) ---
    print("\nRemoving worktrees…")
    try await svc.removeWorktree(repo: repo.path, path: a, force: true)
    try await svc.removeWorktree(repo: repo.path, path: b, force: true)
    let after = try await svc.listWorktrees(repo: repo.path)
    check("back to 1 worktree after cleanup", after.count == 1)

    try? FileManager.default.removeItem(at: tmp)
    print(result.code == 0 ? "\n🎉 POC-1 PASSED — worktree isolation works.\n" : "\n💥 POC-1 had failures.\n")
} catch {
    print("💥 ERROR: \(error)")
    result.code = 1
}

exit(result.code)
