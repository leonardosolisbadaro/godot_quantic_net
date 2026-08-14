#ifndef QN_TYPES_HPP
#define QN_TYPES_HPP

#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <cmath>
#include <unordered_map>
#include <deque>
#include <vector>

using namespace godot;

struct QNEntityState {
    int seq = 0;
    int client_seq = 0;
    int ack = 0;
    bool has_state = false;
    bool is_peer = false;
    Vector3 pos;
    Vector3 rot;
    int custom_id = 0;
    int type = 0;
    Vector3 extents = Vector3(1, 1, 1);
    int ts = 0;
    int last_broadcast_ts = 0;

    Dictionary to_dict() const {
        Dictionary d;
        d["seq"] = seq;
        d["client_seq"] = client_seq;
        d["ack"] = ack;
        d["has_state"] = has_state;
        d["is_peer"] = is_peer;
        d["pos"] = pos;
        d["rot"] = rot;
        d["custom_id"] = custom_id;
        d["type"] = type;
        d["extents"] = extents;
        d["ts"] = ts;
        d["last_broadcast_ts"] = last_broadcast_ts;
        return d;
    }
    
    bool is_empty() const {
        return !has_state;
    }

    bool is_valid() const {
        return has_state &&
               std::isfinite(pos.x) && std::isfinite(pos.y) && std::isfinite(pos.z) &&
               std::isfinite(rot.x) && std::isfinite(rot.y) && std::isfinite(rot.z);
    }
};

struct QNWorldSnapshot {
    int seq = 0;
    std::unordered_map<int, QNEntityState> states;
};

struct QNClientInputState {
    int seq = 0;
    int ack = 0;
    Vector3 pos;
    Vector3 rot;
    int ts = 0;
    int custom_id = 0;

    bool is_valid() const {
        return std::isfinite(pos.x) && std::isfinite(pos.y) && std::isfinite(pos.z) &&
               std::isfinite(rot.x) && std::isfinite(rot.y) && std::isfinite(rot.z);
    }
};

#endif
