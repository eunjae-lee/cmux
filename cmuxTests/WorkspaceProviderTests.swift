import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

// MARK: - Shell Escaping

final class WorkspaceProviderShellEscapeTests: XCTestCase {

    func testSimpleString() {
        let result = WorkspaceProviderExecutor.testableShellEscape("hello")
        XCTAssertEqual(result, "'hello'")
    }

    func testStringWithSpaces() {
        let result = WorkspaceProviderExecutor.testableShellEscape("hello world")
        XCTAssertEqual(result, "'hello world'")
    }

    func testStringWithSingleQuotes() {
        let result = WorkspaceProviderExecutor.testableShellEscape("it's")
        XCTAssertEqual(result, "'it'\\''s'")
    }

    func testEmptyString() {
        let result = WorkspaceProviderExecutor.testableShellEscape("")
        XCTAssertEqual(result, "''")
    }

    func testStringWithSpecialCharacters() {
        let result = WorkspaceProviderExecutor.testableShellEscape("a=b&c|d")
        XCTAssertEqual(result, "'a=b&c|d'")
    }
}

// MARK: - List Response Parsing

final class WorkspaceProviderListParsingTests: XCTestCase {

    func testParseSimpleList() throws {
        let json = """
        {"items":[{"id":"test","name":"Test","subtitle":"~/test"}]}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(WorkspaceProviderListResponse.self, from: data)
        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.items[0].id, "test")
        XCTAssertEqual(response.items[0].name, "Test")
        XCTAssertEqual(response.items[0].subtitle, "~/test")
        XCTAssertNil(response.items[0].inputs)
    }

    func testParseListWithInputs() throws {
        let json = """
        {"items":[{"id":"wt","name":"Worktree","inputs":[
            {"id":"session","label":"Session","required":true},
            {"id":"branch","label":"Branch","deriveFrom":"session"}
        ]}]}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(WorkspaceProviderListResponse.self, from: data)
        XCTAssertEqual(response.items[0].inputs?.count, 2)

        let sessionInput = response.items[0].inputs![0]
        XCTAssertEqual(sessionInput.id, "session")
        XCTAssertTrue(sessionInput.isRequired)
        XCTAssertNil(sessionInput.deriveFrom)

        let branchInput = response.items[0].inputs![1]
        XCTAssertEqual(branchInput.id, "branch")
        XCTAssertFalse(branchInput.isRequired)
        XCTAssertEqual(branchInput.deriveFrom, "session")
    }

    func testParseEmptyList() throws {
        let json = """
        {"items":[]}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(WorkspaceProviderListResponse.self, from: data)
        XCTAssertTrue(response.items.isEmpty)
    }
}

// MARK: - Create Response Parsing

final class WorkspaceProviderCreateParsingTests: XCTestCase {

    func testParseMinimalResult() throws {
        let json = """
        {"title":"Test","cwd":"/tmp/test"}
        """
        let data = json.data(using: .utf8)!
        let result = try JSONDecoder().decode(WorkspaceProviderCreateResult.self, from: data)
        XCTAssertEqual(result.title, "Test")
        XCTAssertEqual(result.cwd, "/tmp/test")
        XCTAssertNil(result.color)
        XCTAssertNil(result.env)
        XCTAssertNil(result.layout)
        XCTAssertFalse(result.isError)
    }

    func testParseErrorResult() throws {
        let json = """
        {"error":"Setup failed"}
        """
        let data = json.data(using: .utf8)!
        let result = try JSONDecoder().decode(WorkspaceProviderCreateResult.self, from: data)
        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.error, "Setup failed")
    }

    func testParseResultWithEnvAndLayout() throws {
        let json = """
        {
            "title":"Test","cwd":"/tmp",
            "color":"#FF0000",
            "env":{"KEY":"VALUE"},
            "layout":{"pane":{"surfaces":[
                {"type":"terminal","name":"Shell"},
                {"type":"terminal","name":"Git","command":"lazygit","suspended":true}
            ]}}
        }
        """
        let data = json.data(using: .utf8)!
        let result = try JSONDecoder().decode(WorkspaceProviderCreateResult.self, from: data)
        XCTAssertEqual(result.color, "#FF0000")
        XCTAssertEqual(result.env?["KEY"], "VALUE")
        XCTAssertNotNil(result.layout)

        if case .pane(let pane) = result.layout {
            XCTAssertEqual(pane.surfaces.count, 2)
            XCTAssertEqual(pane.surfaces[0].name, "Shell")
            XCTAssertNil(pane.surfaces[0].suspended)
            XCTAssertEqual(pane.surfaces[1].command, "lazygit")
            XCTAssertEqual(pane.surfaces[1].suspended, true)
        } else {
            XCTFail("Expected pane layout")
        }
    }

    func testParseSplitLayout() throws {
        let json = """
        {
            "title":"Test","cwd":"/tmp",
            "layout":{
                "direction":"horizontal","split":0.6,
                "children":[
                    {"pane":{"surfaces":[{"type":"terminal","name":"Left"}]}},
                    {"pane":{"surfaces":[{"type":"terminal","name":"Right"}]}}
                ]
            }
        }
        """
        let data = json.data(using: .utf8)!
        let result = try JSONDecoder().decode(WorkspaceProviderCreateResult.self, from: data)

        if case .split(let split) = result.layout {
            XCTAssertEqual(split.direction, .horizontal)
            XCTAssertEqual(split.split, 0.6)
            XCTAssertEqual(split.children.count, 2)
        } else {
            XCTFail("Expected split layout")
        }
    }
}

// MARK: - Provider Origin Persistence

final class WorkspaceProviderOriginPersistenceTests: XCTestCase {

    func testSessionSnapshotRoundTrip() throws {
        let origin = SessionProviderOriginSnapshot(
            providerId: "test-provider",
            destroyCommand: "/usr/bin/destroy",
            itemId: "project::blank",
            inputs: ["session": "feature-x", "branch": "feature-x"],
            cwd: "/tmp/worktree"
        )

        let encoded = try JSONEncoder().encode(origin)
        let decoded = try JSONDecoder().decode(SessionProviderOriginSnapshot.self, from: encoded)

        XCTAssertEqual(decoded.providerId, "test-provider")
        XCTAssertEqual(decoded.destroyCommand, "/usr/bin/destroy")
        XCTAssertEqual(decoded.itemId, "project::blank")
        XCTAssertEqual(decoded.inputs["session"], "feature-x")
        XCTAssertEqual(decoded.cwd, "/tmp/worktree")
    }

    func testSessionSnapshotWithoutOptionals() throws {
        let origin = SessionProviderOriginSnapshot(
            providerId: "test",
            destroyCommand: nil,
            itemId: "simple",
            inputs: [:],
            cwd: nil
        )

        let encoded = try JSONEncoder().encode(origin)
        let decoded = try JSONDecoder().decode(SessionProviderOriginSnapshot.self, from: encoded)

        XCTAssertEqual(decoded.providerId, "test")
        XCTAssertNil(decoded.destroyCommand)
        XCTAssertNil(decoded.cwd)
    }
}

// MARK: - Suspended Layout Persistence

final class SuspendedLayoutPersistenceTests: XCTestCase {

    func testLayoutJSONRoundTrip() throws {
        let layout: CmuxLayoutNode = .pane(CmuxPaneDefinition(surfaces: [
            CmuxSurfaceDefinition(type: .terminal, name: "Shell"),
            CmuxSurfaceDefinition(type: .terminal, name: "Git", command: "lazygit", suspended: true),
        ]))

        let data = try JSONEncoder().encode(layout)
        let jsonString = String(data: data, encoding: .utf8)!
        let restored = try JSONDecoder().decode(CmuxLayoutNode.self, from: jsonString.data(using: .utf8)!)

        if case .pane(let pane) = restored {
            XCTAssertEqual(pane.surfaces.count, 2)
            XCTAssertEqual(pane.surfaces[0].name, "Shell")
            XCTAssertEqual(pane.surfaces[1].suspended, true)
        } else {
            XCTFail("Expected pane layout")
        }
    }

    func testSplitLayoutRoundTrip() throws {
        let layout: CmuxLayoutNode = .split(CmuxSplitDefinition(
            direction: .horizontal,
            split: 0.6,
            children: [
                .pane(CmuxPaneDefinition(surfaces: [
                    CmuxSurfaceDefinition(type: .terminal, name: "Left"),
                ])),
                .pane(CmuxPaneDefinition(surfaces: [
                    CmuxSurfaceDefinition(type: .browser, url: "http://localhost:3000"),
                ])),
            ]
        ))

        let data = try JSONEncoder().encode(layout)
        let restored = try JSONDecoder().decode(CmuxLayoutNode.self, from: data)

        if case .split(let split) = restored {
            XCTAssertEqual(split.direction, .horizontal)
            XCTAssertEqual(split.split, 0.6)
        } else {
            XCTFail("Expected split layout")
        }
    }
}

// MARK: - Provider Config Decoding

final class WorkspaceProviderConfigTests: XCTestCase {

    func testDecodeProviderDefinition() throws {
        let json = """
        {"id":"test","name":"Test","list":"echo list","create":"echo create","destroy":"echo destroy"}
        """
        let data = json.data(using: .utf8)!
        let def = try JSONDecoder().decode(WorkspaceProviderDefinition.self, from: data)
        XCTAssertEqual(def.id, "test")
        XCTAssertEqual(def.name, "Test")
        XCTAssertEqual(def.list, "echo list")
        XCTAssertEqual(def.create, "echo create")
        XCTAssertEqual(def.destroy, "echo destroy")
    }

    func testDecodeProviderWithoutDestroy() throws {
        let json = """
        {"id":"test","name":"Test","list":"echo list","create":"echo create"}
        """
        let data = json.data(using: .utf8)!
        let def = try JSONDecoder().decode(WorkspaceProviderDefinition.self, from: data)
        XCTAssertNil(def.destroy)
    }

    func testDecodeSuspendedSurface() throws {
        let json = """
        {"type":"terminal","name":"Git","command":"lazygit","suspended":true}
        """
        let data = json.data(using: .utf8)!
        let surface = try JSONDecoder().decode(CmuxSurfaceDefinition.self, from: data)
        XCTAssertEqual(surface.suspended, true)
        XCTAssertEqual(surface.command, "lazygit")
    }
}
