var request = require("https").request("https://raw.githubusercontent.com/godotengine/godot/4.3/modules/multiplayer/scene_multiplayer.cpp", (res) => {
	var data = "";
	res.on("data", (chunk) => data += chunk);
	res.on("end", () => {
		var lines = data.split("\n");
		for (var i = 110; i < 140; i++) {
			console.log(i + ": " + lines[i]);
		}
	});
});
request.end();
