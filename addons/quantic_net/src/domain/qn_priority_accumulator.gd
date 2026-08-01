## @file qn_priority_accumulator.gd
## @path res://addons/quantic_net/src/domain/qn_priority_accumulator.gd
##
## @description
## Sistema de priorização de banda (Bandwidth Management).
## Seleciona entidades para envio respeitando o limite de MTU (Maximum Transmission Unit).
## Utiliza pontuação baseada em NetProfile, distância e "débito acumulado" para evitar starvation.
##
## @created 2026-08-01
## @updated 2026-08-01
##
## @since 0.1.0
## @lastModifiedIn 0.1.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends RefCounted

const QNNetProfile = preload("res://addons/quantic_net/src/domain/qn_net_profile.gd")

# Dicionário de débito: _debt[peer_id][entity_id] = float
var _debt := {}

func _get_debt(peer_id: int, entity_id: int) -> float:
	if not _debt.has(peer_id):
		return 0.0
	return _debt[peer_id].get(entity_id, 0.0)

func _add_debt(peer_id: int, entity_id: int, amount: float) -> void:
	if not _debt.has(peer_id):
		_debt[peer_id] = {}
	var current = _debt[peer_id].get(entity_id, 0.0)
	_debt[peer_id][entity_id] = current + amount

func _clear_debt(peer_id: int, entity_id: int) -> void:
	if _debt.has(peer_id) and _debt[peer_id].has(entity_id):
		_debt[peer_id].erase(entity_id)

func _cleanup_peer(peer_id: int) -> void:
	if _debt.has(peer_id):
		_debt.erase(peer_id)

## Seleciona quais entidades entram no pacote atual respeitando o mtu_budget (bytes).
## candidates: Dicionário contendo os current_states (id -> state dict) passados pelo Hybrid Ticking.
## observer_pos: A posição do peer que receberá o pacote (usado para spatial sorting).
## bytes_per_entity: O custo médio em bytes de um delta (19 bytes absolutos, mas delta pode ser menor. Fixaremos um custo conservador).
## Retorna o dicionário filtrado (subconjunto de candidates).
func select_entities(peer_id: int, candidates: Dictionary, profiles: Dictionary, observer_pos: Vector3, mtu_budget: int = 1200, bytes_per_entity: int = 19) -> Dictionary:
	var scored_list := []
	
	for entity_id in candidates:
		var st = candidates[entity_id]
		var pos: Vector3 = st.pos
		var profile: RefCounted = profiles.get(entity_id)
		
		# Parâmetros base do NetProfile
		var base_priority: float = profile.base_priority if profile else 1.0
		var cull_radius: float = profile.spatial_culling_radius if profile else 50.0
		
		var dist: float = observer_pos.distance_to(pos)
		
		# Spatial Culling (descarte imediato se fora da visão, exceto se for o próprio jogador)
		if dist > cull_radius and entity_id != peer_id:
			_add_debt(peer_id, entity_id, 0.1) # Acumula débito bem leve para que não morra de inanição infinita?
			# Na verdade, se estiver fora da visao, nao enviamos. Mas e se precisar atualizar? 
			# Em MMOs estritos, entidades fora da AoI simplesmente nao sao enviadas, e removemos do cliente.
			# Para simplificar agora, so descartamos, mas mantemos pequeno debito para eventual "atualizacao de seguranca".
			continue
			
		# Cálculo do Score
		var distance_factor: float = max(1.0, dist)
		var score: float = (base_priority * 100.0) / distance_factor
		
		# Soma o débito acumulado
		score += _get_debt(peer_id, entity_id)
		
		# O próprio peer deve sempre ter altíssima prioridade para seu eco autoritativo
		if entity_id == peer_id:
			score += 100000.0
			
		scored_list.append({
			"id": entity_id,
			"score": score,
			"state": st
		})
		
	# Ordena por score decrescente
	scored_list.sort_custom(func(a, b): return a.score > b.score)
	
	var selected := {}
	var current_bytes := 0
	
	for item in scored_list:
		if current_bytes + bytes_per_entity <= mtu_budget:
			# Coube no pacote
			selected[item.id] = item.state
			current_bytes += bytes_per_entity
			_clear_debt(peer_id, item.id)
		else:
			# Estourou o pacote! Adiciona débito para a próxima rodada
			_add_debt(peer_id, item.id, item.score * 0.5) # Aumenta a prioridade agressivamente
			
	return selected
