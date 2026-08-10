#include "qn_spatial_grid.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <algorithm>

using namespace godot;

QNSpatialGrid::QNSpatialGrid() {
	cell_size = 50.0;
}

QNSpatialGrid::~QNSpatialGrid() {
}

void QNSpatialGrid::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_cell_size", "size"), &QNSpatialGrid::set_cell_size);
	ClassDB::bind_method(D_METHOD("get_cell_size"), &QNSpatialGrid::get_cell_size);

	ClassDB::bind_method(D_METHOD("insert_entity", "id", "pos"), &QNSpatialGrid::insert_entity);
	ClassDB::bind_method(D_METHOD("update_entity", "id", "pos"), &QNSpatialGrid::update_entity);
	ClassDB::bind_method(D_METHOD("remove_entity", "id"), &QNSpatialGrid::remove_entity);
	ClassDB::bind_method(D_METHOD("get_entities_in_radius", "pos", "radius"), &QNSpatialGrid::get_entities_in_radius);
	ClassDB::bind_method(D_METHOD("set_world_bounds", "extents", "active"), &QNSpatialGrid::set_world_bounds);
	ClassDB::bind_method(D_METHOD("is_in_bounds", "pos"), &QNSpatialGrid::is_in_bounds);
	ClassDB::bind_method(D_METHOD("get_entities_in_chunk", "pos"), &QNSpatialGrid::get_entities_in_chunk);
	ClassDB::bind_method(D_METHOD("get_chunk_coord", "pos"), &QNSpatialGrid::get_chunk_coord);
	ClassDB::bind_method(D_METHOD("clear"), &QNSpatialGrid::clear);

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cell_size"), "set_cell_size", "get_cell_size");
}

uint64_t QNSpatialGrid::_get_cell_key(const Vector3 &pos) const {
	int32_t cx = static_cast<int32_t>(std::floor(pos.x / cell_size));
	int32_t cz = static_cast<int32_t>(std::floor(pos.z / cell_size));
	return (static_cast<uint64_t>(static_cast<uint32_t>(cx)) << 32) | static_cast<uint32_t>(cz);
}

void QNSpatialGrid::set_cell_size(double size) {
	if (size > 0.0) {
		cell_size = size;
		// Resizing clears the grid ideally, but here we just leave it for simplicity.
		// Usually cell_size is configured once.
	}
}

double QNSpatialGrid::get_cell_size() const {
	return cell_size;
}

void QNSpatialGrid::set_world_bounds(const Vector3 &extents, bool active) {
	_world_extents = extents;
	_bounds_active = active;
}

bool QNSpatialGrid::is_in_bounds(const Vector3 &pos) const {
	if (!_bounds_active) return true;
	return (std::abs(pos.x) <= _world_extents.x) &&
		   (std::abs(pos.y) <= _world_extents.y) &&
		   (std::abs(pos.z) <= _world_extents.z);
}

void QNSpatialGrid::insert_entity(int id, const Vector3 &pos) {
	if (!is_in_bounds(pos)) return; // Ignore entities out of bounds
	uint64_t key = _get_cell_key(pos);
	cells[key].push_back(id);
	entity_cells[id] = key;
}

void QNSpatialGrid::update_entity(int id, const Vector3 &pos) {
	auto it = entity_cells.find(id);
	if (it == entity_cells.end()) {
		insert_entity(id, pos);
		return;
	}

	uint64_t old_key = it->second;
	uint64_t new_key = _get_cell_key(pos);

	if (old_key != new_key) {
		// Remove from old cell
		auto &old_vec = cells[old_key];
		old_vec.erase(std::remove(old_vec.begin(), old_vec.end(), id), old_vec.end());
		if (old_vec.empty()) {
			cells.erase(old_key);
		}

		// Insert into new cell
		if (is_in_bounds(pos)) {
			cells[new_key].push_back(id);
			entity_cells[id] = new_key;
		} else {
			entity_cells.erase(id); // Effectively removed from grid due to bounds
		}
	}
}

void QNSpatialGrid::remove_entity(int id) {
	auto it = entity_cells.find(id);
	if (it != entity_cells.end()) {
		uint64_t key = it->second;
		auto &vec = cells[key];
		vec.erase(std::remove(vec.begin(), vec.end(), id), vec.end());
		if (vec.empty()) {
			cells.erase(key);
		}
		entity_cells.erase(it);
	}
}

PackedInt32Array QNSpatialGrid::get_entities_in_radius(const Vector3 &pos, double radius) const {
	PackedInt32Array result;
	
	int32_t min_cx = static_cast<int32_t>(std::floor((pos.x - radius) / cell_size));
	int32_t max_cx = static_cast<int32_t>(std::floor((pos.x + radius) / cell_size));
	int32_t min_cz = static_cast<int32_t>(std::floor((pos.z - radius) / cell_size));
	int32_t max_cz = static_cast<int32_t>(std::floor((pos.z + radius) / cell_size));

	for (int32_t cx = min_cx; cx <= max_cx; ++cx) {
		for (int32_t cz = min_cz; cz <= max_cz; ++cz) {
			uint64_t key = (static_cast<uint64_t>(static_cast<uint32_t>(cx)) << 32) | static_cast<uint32_t>(cz);
			auto it = cells.find(key);
			if (it != cells.end()) {
				for (int id : it->second) {
					result.push_back(id);
				}
			}
		}
	}

	return result;
}

PackedInt32Array QNSpatialGrid::get_entities_in_chunk(const Vector3 &pos) const {
	PackedInt32Array result;
	uint64_t key = _get_cell_key(pos);
	auto it = cells.find(key);
	if (it != cells.end()) {
		for (int id : it->second) {
			result.push_back(id);
		}
	}
	return result;
}

Vector3 QNSpatialGrid::get_chunk_coord(const Vector3 &pos) const {
	int32_t cx = static_cast<int32_t>(std::floor(pos.x / cell_size));
	int32_t cz = static_cast<int32_t>(std::floor(pos.z / cell_size));
	return Vector3(cx, 0, cz);
}

void QNSpatialGrid::clear() {
	cells.clear();
	entity_cells.clear();
}
