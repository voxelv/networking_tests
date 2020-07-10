extends Node

enum pkt_type {PKT_UNKNOWN, PKT_STRING, PKT_COMMAND, PKT_TYPE_COUNT}
enum cmd_type {CMD_NONE, CMD_QUIT}

func make_pkt(type:int, data:Dictionary)->Dictionary:
	var pkt := {}
	if pkt_type.PKT_UNKNOWN < type and type < pkt_type.PKT_TYPE_COUNT:
		pkt['type'] = type
	
	match type:
		pkt_type.PKT_STRING:
			pkt['string'] = data.get('string', "")
		pkt_type.PKT_COMMAND:
			pkt['command'] = data.get('command', cmd_type.CMD_NONE)
		pkt_type.PKT_UNKNOWN, _:
			assert(type == pkt_type.PKT_UNKNOWN)
			pkt['type'] = pkt_type.PKT_UNKNOWN
	return pkt

func parse_pkt(pkt:Dictionary)->Dictionary:
	var result := {}
	var type := pkt.get('type', pkt_type.PKT_UNKNOWN) as int
	
	result['type'] = type
	match type:
		pkt_type.PKT_STRING:
			result['string'] = pkt.get('string', "")
		pkt_type.PKT_COMMAND:
			result['command'] = pkt.get('command', cmd_type.CMD_NONE)
		pkt_type.PKT_UNKNOWN, _:
			pass
	
	return result

