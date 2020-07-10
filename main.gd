extends Node
enum {NET_NONE, NET_SERVER, NET_CLIENT}
const INVALID_PEERID := -1
const URL := "localhost"
const PORT_PREFIX := "port="
const PORT := 9080
const PID_PREFIX := "pid="
const PEERID_PREFIX := "peerid="
const CONTROL_MODE_SERVER := "SERVER"
const CONTROL_MODE_CLIENT := "CLIENT"
const QUIT_PREFIX := "QUIT"

export(int) var MAX_MESSAGES := 5

var cli_args:PoolStringArray
var control_mode := NET_NONE
var _socket:WebSocketMultiplayerPeer
var pid_to_peerid := {}
var port_to_use := PORT
var client_peerid := -1
var autoscroll := false

onready var messages_list = find_node("messages_list")
onready var scroll_container = find_node("scroll_container")

func _init()->void:
	cli_args = OS.get_cmdline_args()
	
	# Determine control_mode
	for arg in cli_args:
		var a := (arg as String).strip_edges()
		if CONTROL_MODE_CLIENT in a:
			control_mode = NET_CLIENT
		if CONTROL_MODE_SERVER in a:
			control_mode = NET_SERVER
			
	# Assume Server if no args given
	if len(cli_args) < 1:
		control_mode = NET_SERVER
	
	match control_mode:
		NET_CLIENT:
			OS.set_window_title("CLIENT")
			_socket = WebSocketClient.new()
			
		NET_SERVER:
			OS.set_window_title("SERVER")
			_socket = WebSocketServer.new()

func _spawn_client()->void:
	var client_args := ["CLIENT", "%s%s" % [PORT_PREFIX, PORT]]
	var p := OS.get_executable_path()
	var c_pid = OS.execute(p, client_args, false)
	print("Client with pid: %s spawned with args: %s" % [c_pid, str(client_args)])
	pid_to_peerid[c_pid] = INVALID_PEERID

func _request_client_quit(pid:int)->void:
	var pkt := PKT.make_pkt(
		PKT.pkt_type.PKT_COMMAND, 
		{'command': PKT.cmd_type.CMD_QUIT})
	_socket.get_peer(pid_to_peerid[pid]).put_var(pkt)

func _ready() -> void:
	for i in range(len(cli_args)):
		add_message("arg %s: %s" % [i, cli_args[i]])
		
		if PORT_PREFIX in cli_args[i]:
			port_to_use = int(cli_args[i].replace(PORT_PREFIX, ""))
	
	# Connect signals
	match control_mode:
		NET_SERVER:
			_socket.connect("client_connected", self, "_client_connected")
			_socket.connect("client_disconnected", self, "_disconnected")
			_socket.connect("client_close_request", self, "_close_request")
			_socket.connect("data_received", self, "_on_data_from_client")
		NET_CLIENT:
			_socket.connect("connection_closed", self, "_closed")
			_socket.connect("connection_error", self, "_closed")
			_socket.connect("connection_established", self, "_connected_to_server")
			_socket.connect("data_received", self, "_on_data_from_server")
	
	# Start Socket
	var err:int
	match control_mode:
		NET_SERVER:
			err = (_socket as WebSocketServer).listen(port_to_use)
			if err != OK:
				set_process(false)
		NET_CLIENT:
			_client_attempt_connection()
	_socket.set_allow_object_decoding(true)
	
	# Add special stuff
	match control_mode:
		NET_SERVER:
			var b = Button.new()
			b.text = "SPAWN CLIENT"
			find_node("top_button_list").add_child(b)
			b.connect("pressed", self, "_spawn_client")

# Server-only
func _client_connected(id, proto):
	var s := "Client %d connected with protocol: %s" % [id, proto]
	print(s)
	add_message(s)
	
func _close_request(id, code, reason):
	var s := "Client %d disconnecting with code: %d, reason: %s" % [id, code, reason]
	print(s)
	add_message(s)
	
func _disconnected(id, was_clean = false):
	var s := "Client %d disconnected, clean: %s" % [id, str(was_clean)]
	print(s)
	add_message(s)
	var c_pid := -1
	for pid in pid_to_peerid.keys():
		if pid_to_peerid[pid] == id:
			c_pid = pid
			break
	pid_to_peerid.erase(c_pid)
	
func _on_data_from_client(id):
	var pkt := _socket.get_peer(id).get_var() as Dictionary
	var s := ""
	match pkt.get('type', PKT.pkt_type.PKT_UNKNOWN):
		PKT.pkt_type.PKT_STRING:
			s = pkt['string']
		PKT.pkt_type.PKT_UNKNOWN, _:
			pass
	add_message("Client %d: %s" % [id, s])
	
	if PID_PREFIX in s:
		var pid:int
		pid = int(s.replace(PID_PREFIX, ""))
		pid_to_peerid[pid] = id
		var peerid_data := "%s%d" % [PEERID_PREFIX, id]
		pkt = PKT.make_pkt(PKT.pkt_type.PKT_STRING, {'string':peerid_data})
		_socket.get_peer(id).put_var(pkt)

# Client-only
func _client_attempt_connection()->void:
	var status := _socket.get_connection_status()
	if status != NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	add_message("Connecting...")
	set_process(true)
	var err := (_socket as WebSocketClient).connect_to_url("%s:%d" % [URL, port_to_use])
	if err != OK:
		set_process(false)

func _closed(was_clean:bool=false):
	print("Client %d closed, clean: " % client_peerid, was_clean)
	set_process(false)
	
func _connected_to_server(proto:String):
	add_message("Connected (%s)." % proto)
	var data := "%s%s" % [PID_PREFIX, OS.get_process_id()]
	var pkt := PKT.make_pkt(PKT.pkt_type.PKT_STRING, {'string':data})
	_socket.get_peer(1).put_var(pkt)
	
func _on_data_from_server():
	var pkt := _socket.get_peer(1).get_var() as Dictionary
	print(str(pkt))
	_socket.get_peer(1).put_var(pkt)
	
	match pkt['type']:
		PKT.pkt_type.PKT_STRING:
			var s := pkt['string'] as String
			add_message(s)
			if PEERID_PREFIX in s:
				client_peerid = int(s.replace(PEERID_PREFIX, ""))
				_update_client_peerid()
		PKT.pkt_type.PKT_COMMAND:
			match pkt['command']:
				PKT.cmd_type.CMD_QUIT:
					get_tree().quit()
				_:
					pass
		PKT.pkt_type.PKT_UNKNOWN, _:
			pass

func _update_client_peerid()->void:
	var s := "CLIENT %d" % client_peerid
	OS.set_window_title(s)

func add_message(msg:String)->void:
	var l:Label
	if messages_list.get_child_count() >= MAX_MESSAGES:
		while messages_list.get_child_count() > MAX_MESSAGES:
			var c = messages_list.get_child(0)
			messages_list.remove_child(c)
			c.queue_free()
		l = messages_list.get_child(0)
		messages_list.remove_child(l)
	else:
		l = Label.new()
		
	l.text = msg
	messages_list.add_child(l)
	
	if autoscroll:
		call_deferred("_autoscroll_deferred")

func _autoscroll_deferred()->void:
	yield(get_tree(), "idle_frame")
	scroll_container.set_v_scroll(scroll_container.get_v_scrollbar().get_max())

func _process(delta: float) -> void:
	_socket.poll()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PREDELETE, NOTIFICATION_CRASH, NOTIFICATION_EXIT_TREE, NOTIFICATION_WM_QUIT_REQUEST:
			match control_mode:
				NET_SERVER:
					for c_pid in pid_to_peerid.keys():
#						var ret := OS.kill(c_pid)
#						print("Child with pid: %s exited with code: %s" % [str(c_pid), str(ret)])
						_request_client_quit(c_pid)
						(_socket as WebSocketServer).disconnect_peer(pid_to_peerid[c_pid])
					pid_to_peerid.clear()
					
				NET_CLIENT:
					var reasons := {
						NOTIFICATION_PREDELETE:"PREDELETE",
						NOTIFICATION_CRASH:"CRASH",
						NOTIFICATION_EXIT_TREE:"EXIT_TREE",
						NOTIFICATION_WM_QUIT_REQUEST:"WM_QUIT_REQUEST",
						}
					(_socket as WebSocketClient).disconnect_from_host(0, "X")

func _on_pressme_button_pressed() -> void:
	var data := ""
	match control_mode:
		NET_SERVER:
			data = "SERVER BROADCAST"
			for peerid in pid_to_peerid.values():
				if peerid != INVALID_PEERID:
					var pkt := PKT.make_pkt(PKT.pkt_type.PKT_STRING, {'string':data})
					_socket.get_peer(peerid).put_var(pkt)
		NET_CLIENT:
			data = "CLIENT TO SERVER"
			var pkt := PKT.make_pkt(PKT.pkt_type.PKT_STRING, {'string':data})
			_socket.get_peer(1).put_var(pkt)

func _on_autoscroll_checkbox_toggled(button_pressed: bool) -> void:
	autoscroll = button_pressed

func _on_clear_button_pressed() -> void:
	for c in messages_list.get_children():
		c.queue_free()

func _on_send_button_pressed() -> void:
	var s := (find_node("entry_line") as LineEdit).text
	var pkt := PKT.make_pkt(PKT.pkt_type.PKT_STRING, {'string':s})
	_socket.get_peer(1).put_var(pkt)


func _on_reconnect_timer_timeout() -> void:
	match control_mode:
		NET_CLIENT:
			_client_attempt_connection()
