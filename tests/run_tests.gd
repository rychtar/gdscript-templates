extends SceneTree

# Runs every test_*.gd in this folder, each method starting with "test_" is one test:
#   godot --headless --path . --script tests/run_tests.gd
# Exits with code 1 when a test fails.

const TESTS_DIR = "res://tests"

func _init() -> void:
	_run()

func _run() -> void:
	var total := 0
	var failed := 0
	for file in _test_files():
		var test = load(TESTS_DIR.path_join(file)).new()
		test.tree = self
		for method in test.get_method_list():
			if not method.name.begins_with("test_"):
				continue
			total += 1
			test.failures.clear()
			# a test can await signals (a frame, for example)
			await test.call(method.name)
			test.cleanup()
			if not test.failures.is_empty():
				failed += 1
				print("FAIL %s::%s" % [file, method.name])
				for failure in test.failures:
					print("  " + failure.replace("\n", "\n  "))

	print("%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)

func _test_files() -> PackedStringArray:
	var files := PackedStringArray()
	for file in DirAccess.get_files_at(TESTS_DIR):
		if file.begins_with("test_") and file.ends_with(".gd"):
			files.append(file)
	files.sort()
	return files
