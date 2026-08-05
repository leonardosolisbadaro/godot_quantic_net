#ifndef QN_SPATIAL_GRID_H
#define QN_SPATIAL_GRID_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <unordered_map>
#include <vector>

namespace godot {

class QNSpatialGrid : public RefCounted {
	GDCLASS(QNSpatialGrid, RefCounted)

private:
	double cell_size;
	std::unordered_map<uint64_t, std::vector<int>> cells;
	std::unordered_map<int, uint64_t> entity_cells;

	uint64_t _get_cell_key(const Vector3 &pos) const;

protected:
	static void _bind_methods();

public:
	QNSpatialGrid();
	~QNSpatialGrid();

	void set_cell_size(double size);
	double get_cell_size() const;

	void insert_entity(int id, const Vector3 &pos);
	void update_entity(int id, const Vector3 &pos);
	void remove_entity(int id);
	
	PackedInt32Array get_entities_in_radius(const Vector3 &pos, double radius) const;
	void clear();
};

} // namespace godot

#endif // QN_SPATIAL_GRID_H
