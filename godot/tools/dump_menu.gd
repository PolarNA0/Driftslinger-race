extends SceneTree

# Headless menu dump: builds the real menu scene and prints every Button label,
# so the port's menu can be diffed against the web build's.

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var root_node := scene.instantiate()
	get_root().add_child(root_node)
	await process_frame
	await process_frame
	_dump(root_node, 0)
	quit()

func _dump(node: Node, depth: int) -> void:
	if node is Button:
		var b := node as Button
		var txt := b.text.replace("\n", " | ")
		print("%s[Button] %s" % ["  ".repeat(depth), txt])
	if node is ScrollContainer or node is GridContainer or node is VBoxContainer or node is HBoxContainer or node is Control:
		pass
	for c in node.get_children():
		_dump(c, depth + 1)
