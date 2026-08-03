extends Node3D

# LTD client — connects to the Node.js server (server/server.js) over WebSocket.
# The server is authoritative; this script only sends join/move and renders state.

const PLAYER_SIZE := 1.0 # player cube is 2x the yellow cube
const CUBE_SIZE := 0.5
const BOUND := 18.0 # must match server BOUND
const LERP_SPEED := 12.0

const PLAYER_COLORS := {
	"red": Color(0.85, 0.1, 0.1),
	"blue": Color(0.15, 0.3, 0.9),
	"white": Color(0.95, 0.95, 0.95),
	"black": Color(0.08, 0.08, 0.08),
}

@onready var camera: Camera3D = $Camera3D
@onready var connect_panel: CenterContainer = $UI/ConnectPanel
@onready var ip_edit: LineEdit = %IpEdit
@onready var port_edit: LineEdit = %PortEdit
@onready var name_edit: LineEdit = %NameEdit
@onready var connect_button: Button = %ConnectButton
@onready var status_label: Label = %StatusLabel
@onready var score_label: Label = $UI/ScoreLabel

var socket: WebSocketPeer
var joined := false
var my_id := -1
var player_nodes := {} # id -> {node: MeshInstance3D, target: Vector3}
var cube_node: MeshInstance3D


func _ready() -> void:
	connect_button.pressed.connect(_on_connect_pressed)
	score_label.visible = false


func _on_connect_pressed() -> void:
	var ip := ip_edit.text.strip_edges()
	var port := port_edit.text.strip_edges()
	if ip.is_empty() or not port.is_valid_int():
		status_label.text = "Enter a valid IP and port."
		return
	socket = WebSocketPeer.new()
	var err := socket.connect_to_url("ws://%s:%s" % [ip, port])
	if err != OK:
		status_label.text = "Connection failed (error %d)." % err
		socket = null
		return
	status_label.text = "Connecting..."
	connect_button.disabled = true


func _process(delta: float) -> void:
	_poll_socket()

	for id in player_nodes:
		var entry: Dictionary = player_nodes[id]
		var node: MeshInstance3D = entry.node
		node.position = node.position.lerp(entry.target, minf(1.0, delta * LERP_SPEED))

	if cube_node:
		cube_node.rotate_y(delta * 2.0)


func _poll_socket() -> void:
	if socket == null:
		return
	socket.poll()
	match socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not joined:
				joined = true
				var player_name := name_edit.text.strip_edges()
				if player_name.is_empty():
					player_name = "Player"
				socket.send_text(JSON.stringify({"type": "join", "name": player_name}))
			while socket.get_available_packet_count() > 0:
				var msg = JSON.parse_string(socket.get_packet().get_string_from_utf8())
				if msg is Dictionary:
					_handle_message(msg)
		WebSocketPeer.STATE_CLOSED:
			var was_joined := my_id != -1
			var code := socket.get_close_code()
			socket = null
			joined = false
			my_id = -1
			_clear_world()
			connect_panel.visible = true
			score_label.visible = false
			connect_button.disabled = false
			if status_label.text != "Server is full (max 4 players).":
				if was_joined:
					status_label.text = "Disconnected from server."
				elif code == -1:
					status_label.text = "Could not reach server."
				else:
					status_label.text = "Connection closed."


func _handle_message(msg: Dictionary) -> void:
	match msg.get("type"):
		"welcome":
			my_id = int(msg.id)
			connect_panel.visible = false
			score_label.visible = true
		"full":
			status_label.text = "Server is full (max 4 players)."
		"state":
			_apply_state(msg)
		"pickup":
			pass # scores arrive via state; hook sounds/effects here later


func _apply_state(state: Dictionary) -> void:
	var seen := {}
	for p in state.players:
		var id := int(p.id)
		seen[id] = true
		var pos := Vector3(p.x, PLAYER_SIZE / 2.0, p.z)
		if not player_nodes.has(id):
			player_nodes[id] = {
				"node": _make_player_node(str(p.name), str(p.color), id == my_id, pos),
				"target": pos,
			}
		else:
			player_nodes[id].target = pos

	for id in player_nodes.keys():
		if not seen.has(id):
			player_nodes[id].node.queue_free()
			player_nodes.erase(id)

	var cube = state.get("cube")
	if cube is Dictionary:
		if cube_node == null:
			cube_node = _make_box(CUBE_SIZE, Color(1.0, 0.85, 0.1))
			add_child(cube_node)
		cube_node.position = Vector3(cube.x, CUBE_SIZE / 2.0, cube.z)
	elif cube_node:
		cube_node.queue_free()
		cube_node = null

	_update_scoreboard(state.players)


func _make_player_node(player_name: String, color_name: String, is_me: bool, pos: Vector3) -> MeshInstance3D:
	var node := _make_box(PLAYER_SIZE, PLAYER_COLORS.get(color_name, Color.MAGENTA))
	node.position = pos
	var label := Label3D.new()
	label.text = player_name + (" (you)" if is_me else "")
	label.position.y = PLAYER_SIZE + 0.4
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.pixel_size = 0.01
	label.outline_size = 16
	node.add_child(label)
	add_child(node)
	return node


func _make_box(size: float, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	mesh_instance.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_instance.material_override = mat
	return mesh_instance


func _update_scoreboard(players: Array) -> void:
	var lines := PackedStringArray(["SCORES"])
	for p in players:
		var marker := "  <- you" if int(p.id) == my_id else ""
		lines.append("%s  %s: %d%s" % [str(p.color).capitalize(), p.name, int(p.score), marker])
	score_label.text = "\n".join(lines)


func _clear_world() -> void:
	for id in player_nodes:
		player_nodes[id].node.queue_free()
	player_nodes.clear()
	if cube_node:
		cube_node.queue_free()
		cube_node = null
	score_label.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if my_id == -1 or socket == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var origin := camera.project_ray_origin(event.position)
		var dir := camera.project_ray_normal(event.position)
		if dir.y >= -0.0001:
			return
		var hit := origin + dir * (-origin.y / dir.y)
		socket.send_text(JSON.stringify({
			"type": "move",
			"x": clampf(hit.x, -BOUND, BOUND),
			"z": clampf(hit.z, -BOUND, BOUND),
		}))
