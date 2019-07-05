//
//  TaskSpec.swift
//  ReactiveTask
//
//  Created by Justin Spahr-Summers on 2014-10-11.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

// swiftlint:disable function_body_length

import Foundation
import Nimble
import Quick
import ReactiveSwift
import ReactiveTask

class TaskSpec: QuickSpec {
	override func spec() {
		it("should notify that a task is about to be launched") {
			var isLaunched: Bool = false

			let task = Task("/usr/bin/true")
			let result = task.launch()
				.on(value: { event in
					if case let .launch(launched) = event {
						isLaunched = true
						expect(launched) == task
					}
				})
				.wait()

			expect(result.error).to(beNil())
			expect(isLaunched) == true
		}

		it("should launch a task that writes to stdout") {
			let result = Task("/bin/echo", arguments: [ "foobar" ]).launch()
				.reduce(Data()) { aggregated, event in
					var mutableData = aggregated
					if case let .standardOutput(data) = event {
						mutableData.append(data)
					}

					return mutableData
				}
				.single()

			expect(result).notTo(beNil())
			if let data = result?.value {
				expect(String(data: data, encoding: .utf8)).to(equal("foobar\n"))
			}
		}

		it("should launch a task that writes to stderr") {
			var aggregated = Data()
			let result = Task("/usr/bin/stat", arguments: [ "not-a-real-file" ]).launch()
				.reduce(aggregated) { _, event in
					if case let .standardError(data) = event {
						aggregated.append(data)
					}
					return aggregated
				}
				.single()

			expect(result).notTo(beNil())
			expect(result?.error).notTo(beNil())
			expect(String(data: aggregated, encoding: .utf8)).to(equal("stat: not-a-real-file: stat: No such file or directory\n"))
		}

		it("should launch a task with standard input") {
			let strings = [ "foo\n", "bar\n", "buzz\n", "fuzz\n" ]
			let data = strings.map { $0.data(using: .utf8)! }

			let result = Task("/usr/bin/sort").launch(standardInput: SignalProducer(data))
				.filterMap { event in event.value }
				.single()

			expect(result).notTo(beNil())
			if let data = result?.value {
				expect(String(data: data, encoding: .utf8)).to(equal("bar\nbuzz\nfoo\nfuzz\n"))
			}
		}

		it("should error correctly") {
			let task = Task("/usr/bin/stat", arguments: [ "not-a-real-file" ])
			let result = task.launch()
				.wait()

			expect(result).notTo(beNil())
			expect(result.error).notTo(beNil())

			let stdError = "stat: not-a-real-file: stat: No such file or directory\n"
			expect(result.error) == TaskError.shellTaskFailed(task, exitCode: 1, standardError: stdError)
			if let error = result.error {
				let expectedDescription =
					"A shell task (/usr/bin/stat not-a-real-file) failed with exit code 1:\n" +
					"stat: not-a-real-file: stat: No such file or directory\n"
				expect(error.description) == expectedDescription
			}
		}

		it("should fail correctly with an invalid task") {
			let task = Task("/usr/bin/non-existent-command", arguments: [ "foo" ])
			let result = task.launch()
				.wait()

			expect(result).notTo(beNil())
			expect(result.error).notTo(beNil())
			if let error = result.error {

				guard case let TaskError.launchFailed(errorTask, _) = error else {
					fail("Expected launchFailed error to be received")
					return
				}

				expect(errorTask) == task
				let expectedPrefix = "A shell task (/usr/bin/non-existent-command foo) failed to launch:\n"
				expect(error.description.hasPrefix(expectedPrefix)).to(beTrue())
			}
		}
	}
}
