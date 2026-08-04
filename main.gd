extends Node3D

# LTD client. Screens: connect -> lobby (rooms / players / chat) -> game ->
# scoreboard -> back to lobby. The server (server/server.js) is authoritative;
# this script only sends intents and renders broadcast state.

const PLAYER_SIZE := 1.0 # player cube is 2x the yellow cube
const CUBE_SIZE := 0.5
const BOUND := 18.0 # must match server BOUND
const LERP_SPEED := 12.0

const PLAYER_COLORS := {
	"red": Color(0.85, 0.1, 0.1),
	"blue": Color(0.15, 0.3, 0.9),
	"white": Color(0.95, 0.95, 0.95),
	"black": Color(0.08, 0.08, 0.08),
	"green": Color(0.15, 0.65, 0.2),
	"orange": Color(0.95, 0.55, 0.1),
	"purple": Color(0.55, 0.2, 0.8),
	"cyan": Color(0.15, 0.75, 0.8),
}

enum Screen { CONNECT, LOBBY, GAME, SCOREBOARD }

@onready var camera: Camera3D = $Camera3D
# Connect screen
@onready var connect_panel: Control = $UI/ConnectPanel
@onready var ip_edit: LineEdit = %IpEdit
@onready var port_edit: LineEdit = %PortEdit
@onready var name_edit: LineEdit = %NameEdit
@onready var connect_button: Button = %ConnectButton
@onready var status_label: Label = %StatusLabel
# Lobby screen
@onready var lobby_panel: Control = $UI/LobbyPanel
@onready var room_list: VBoxContainer = %RoomList
@onready var room_name_edit: LineEdit = %RoomNameEdit
@onready var room_pass_edit: LineEdit = %RoomPassEdit
@onready var max_score_spin: SpinBox = %MaxScoreSpin
@onready var create_button: Button = %CreateButton
@onready var lobby_status: Label = %LobbyStatus
@onready var player_list: ItemList = %PlayerList
@onready var chat_log: RichTextLabel = %ChatLog
@onready var chat_edit: LineEdit = %ChatEdit
@onready var send_button: Button = %SendButton
# Password prompt
@onready var password_panel: Control = $UI/PasswordPanel
@onready var pw_title: Label = %PwTitle
@onready var pw_edit: LineEdit = %PwEdit
@onready var pw_join_button: Button = %PwJoinButton
@onready var pw_cancel_button: Button = %PwCancelButton
# Game screen
@onready var game_ui: Control = $UI/GameUI
@onready var score_label: Label = %ScoreLabel
@onready var leave_button: Button = %LeaveButton
# Scoreboard screen
@onready var scoreboard_panel: Control = $UI/ScoreboardPanel
@onready var scoreboard_title: Label = %ScoreboardTitle
@onready var scoreboard_text: Label = %ScoreboardText
@onready var scoreboard_close: Button = %ScoreboardClose

var socket: WebSocketPeer
var connected_url := ""
var login_sent := false
var screen: Screen = Screen.CONNECT
var my_id := -1
var room_max_score := 0
var player_nodes := {} # id -> {node: MeshInstance3D, target: Vector3}
var cube_node: MeshInstance3D
var last_rooms_json := ""
var pw_room_id := -1


func _ready() -> void:
	connect_button.pressed.connect(_on_connect_pressed)
	create_button.pressed.connect(_on_create_pressed)
	send_button.pressed.connect(_on_chat_send)
	chat_edit.text_submitted.connect(func(_t: String): _on_chat_send())
	pw_join_button.pressed.connect(_on_pw_join)
	pw_cancel_button.pressed.connect(func(): password_panel.visible = false)
	leave_button.pressed.connect(_on_leave_pressed)
	scoreboard_close.pressed.connect(func(): _show_screen(Screen.LOBBY))
	_show_screen(Screen.CONNECT)


func _show_screen(s: Screen) -> void:
	screen = s
	connect_panel.visible = s == Screen.CONNECT
	lobby_panel.visible = s == Screen.LOBBY
	game_ui.visible = s == Screen.GAME
	scoreboard_panel.visible = s == Screen.SCOREBOARD
	password_panel.visible = false
	if s == Screen.CONNECT:
		connect_button.disabled = false


func _send(obj: Dictionary) -> void:
	if socket and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify(obj))


# --- Connect screen ---

func _on_connect_pressed() -> void:
	var ip := ip_edit.text.strip_edges()
	var port := port_edit.text.strip_edges()
	if ip.is_empty() or not port.is_valid_int():
		status_label.text = "Enter a valid IP and port."
		return
	if name_edit.text.strip_edges().is_empty():
		status_label.text = "Enter a name."
		return
	var url := "ws://%s:%s" % [ip, port]
	if socket and socket.get_ready_state() == WebSocketPeer.STATE_OPEN and url == connected_url:
		_send_login()
		return
	socket = WebSocketPeer.new()
	if socket.connect_to_url(url) != OK:
		status_label.text = "Connection failed."
		socket = null
		return
	connected_url = url
	login_sent = false
	status_label.text = "Connecting..."
	connect_button.disabled = true


func _send_login() -> void:
	login_sent = true
	status_label.text = "Checking name..."
	_send({"type": "login", "name": name_edit.text.strip_edges()})


# --- Socket ---

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
			if not login_sent:
				_send_login()
			while socket.get_available_packet_count() > 0:
				var msg = JSON.parse_string(socket.get_packet().get_string_from_utf8())
				if msg is Dictionary:
					_handle_message(msg)
		WebSocketPeer.STATE_CLOSED:
			socket = null
			connected_url = ""
			login_sent = false
			my_id = -1
			_clear_world()
			chat_log.text = ""
			last_rooms_json = ""
			_show_screen(Screen.CONNECT)
			status_label.text = "Disconnected from server."


func _handle_message(msg: Dictionary) -> void:
	match msg.get("type"):
		"login_ok":
			_show_screen(Screen.LOBBY)
			lobby_status.text = ""
		"login_error":
			status_label.text = str(msg.reason)
			connect_button.disabled = false
		"lobby":
			if screen == Screen.LOBBY or screen == Screen.SCOREBOARD:
				_update_rooms(msg.rooms)
				_update_players(msg.players)
		"chat_history":
			chat_log.text = ""
			for m in msg.messages:
				_append_chat(str(m.from), str(m.text))
		"chat":
			_append_chat(str(msg.from), str(msg.text))
		"join_ok":
			my_id = int(msg.id)
			room_max_score = int(msg.room.max_score)
			_clear_world()
			_show_screen(Screen.GAME)
		"join_error", "create_error":
			lobby_status.text = str(msg.reason)
		"state":
			if screen == Screen.GAME:
				_apply_state(msg)
		"pickup":
			pass # scores arrive via state; hook sounds/effects here later
		"game_over":
			_show_game_over(msg)


# --- Lobby ---

func _update_rooms(rooms: Array) -> void:
	var as_json := JSON.stringify(rooms)
	if as_json == last_rooms_json:
		return
	last_rooms_json = as_json
	for child in room_list.get_children():
		child.queue_free()
	for r in rooms:
		var row := HBoxContainer.new()
		var label := Label.new()
		var extras := "  [locked]" if bool(r.has_password) else ""
		label.text = "%s   %d/%d   first to %d%s" % [str(r.name), int(r.players), int(r.max_players), int(r.max_score), extras]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var join := Button.new()
		join.text = "Join"
		join.disabled = int(r.players) >= int(r.max_players)
		join.pressed.connect(_on_join_room.bind(int(r.id), str(r.name), bool(r.has_password)))
		row.add_child(label)
		row.add_child(join)
		room_list.add_child(row)


func _update_players(players: Array) -> void:
	player_list.clear()
	for p in players:
		var where = "in %s" % str(p.room) if p.room != null else "lobby"
		player_list.add_item("%s  (%s)" % [str(p.name), where], null, false)


func _append_chat(from: String, text: String) -> void:
	if chat_log.text.length() > 0:
		chat_log.text += "\n"
	chat_log.text += "%s: %s" % [from, text]


func _on_chat_send() -> void:
	var text := chat_edit.text.strip_edges()
	if text.is_empty():
		return
	_send({"type": "chat", "text": text})
	chat_edit.text = ""


func _on_create_pressed() -> void:
	lobby_status.text = ""
	_send({
		"type": "create_room",
		"name": room_name_edit.text.strip_edges(),
		"password": room_pass_edit.text,
		"max_score": int(max_score_spin.value),
	})


func _on_join_room(id: int, room_name: String, locked: bool) -> void:
	lobby_status.text = ""
	if locked:
		pw_room_id = id
		pw_title.text = "Password for %s" % room_name
		pw_edit.text = ""
		password_panel.visible = true
		pw_edit.grab_focus()
	else:
		_send({"type": "join_room", "id": id})


func _on_pw_join() -> void:
	password_panel.visible = false
	_send({"type": "join_room", "id": pw_room_id, "password": pw_edit.text})


# --- Game ---

func _apply_state(state: Dictionary) -> void:
	var seen := {}
	for p in state.players:
		var id := int(p.id)
		seen[id] = true
		var pos := Vector3(p.x, PLAYER_SIZE / 2.0, p.z)
		if not player_nodes.has(id):
			player_nodes[id] = {
				"node": _make_player_node(str(p.name), str(p.color), bool(p.bot), id == my_id, pos),
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

	var lines := PackedStringArray(["FIRST TO %d" % room_max_score])
	for p in state.players:
		var marker := "  <- you" if int(p.id) == my_id else ""
		var bot_tag := " [bot]" if bool(p.bot) else ""
		lines.append("%s  %s%s: %d%s" % [str(p.color).capitalize(), str(p.name), bot_tag, int(p.score), marker])
	score_label.text = "\n".join(lines)


func _make_player_node(player_name: String, color_name: String, is_bot: bool, is_me: bool, pos: Vector3) -> MeshInstance3D:
	var node := _make_box(PLAYER_SIZE, PLAYER_COLORS.get(color_name, Color.MAGENTA))
	node.position = pos
	var label := Label3D.new()
	var suffix := " (you)" if is_me else (" [bot]" if is_bot else "")
	label.text = player_name + suffix
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


func _clear_world() -> void:
	for id in player_nodes:
		player_nodes[id].node.queue_free()
	player_nodes.clear()
	if cube_node:
		cube_node.queue_free()
		cube_node = null
	score_label.text = ""


func _on_leave_pressed() -> void:
	_send({"type": "leave_room"})
	my_id = -1
	_clear_world()
	_show_screen(Screen.LOBBY)


func _show_game_over(msg: Dictionary) -> void:
	my_id = -1
	_clear_world()
	scoreboard_title.text = "%s wins!" % str(msg.winner.name)
	var lines := PackedStringArray()
	var rank := 1
	for s in msg.scores:
		var bot_tag := " [bot]" if bool(s.bot) else ""
		lines.append("%d.  %s%s  (%s)  -  %d" % [rank, str(s.name), bot_tag, str(s.color), int(s.score)])
		rank += 1
	scoreboard_text.text = "\n".join(lines)
	_show_screen(Screen.SCOREBOARD)


func _unhandled_input(event: InputEvent) -> void:
	if screen != Screen.GAME or my_id == -1 or socket == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var origin := camera.project_ray_origin(event.position)
		var dir := camera.project_ray_normal(event.position)
		if dir.y >= -0.0001:
			return
		var hit := origin + dir * (-origin.y / dir.y)
		_send({
			"type": "move",
			"x": clampf(hit.x, -BOUND, BOUND),
			"z": clampf(hit.z, -BOUND, BOUND),
		})
