extends SceneTree
class _Dummy:
	func validate(p, pos, rot, now):
		return {'action': 'accept', 'pos': pos, 'rot': rot}
func _init():
	var host = preload('res://addons/quantic_net/src/use_cases/qn_host_session.gd').new()
	var validator = _Dummy.new()
	host.validator = validator
	host.on_peer_authenticated(2)
	
	var data = PackedByteArray([0x01, 0x02, 0x00, 0x62, 0x80, 0x00, 0x80, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xb5, 0x3a, 0x00, 0x00, 0x00])
	host.on_client_snapshot(2, data.slice(1), 1000)
	print('REGISTRY: ', host.get_registry())
	quit()
