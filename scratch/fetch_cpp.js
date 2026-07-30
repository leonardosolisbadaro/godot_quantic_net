var request = require("https").request("https://raw.githubusercontent.com/godotengine/godot/4.3/modules/multiplayer/scene_multiplayer.h", (res) => {
	var data = "";
	res.on("data", (chunk) => data += chunk);
	res.on("end", () => {
		var lines = data.split("\n");
		var inEnum = false;
		for (var i = 0; i < lines.length; i++) {
			if (lines[i].includes("NETWORK_COMMAND_")) {
				inEnum = true;
			}
			if (inEnum) {
				console.log(lines[i]);
				if (lines[i].includes("}")) break;
			}
		}
	});
});
request.end();
