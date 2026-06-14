package jaxe;

enum PrintPrefixMode {
	SOURCE;  // Formats like: source/meta/states/Script.java: Message
	SCRIPT;  // Formats like: [Jaxe Script]: Message
	CUSTOM(prefix:String);
}

class JaxeConfig {
	// Change trace and println styling
	public static var PRINT_PREFIX:PrintPrefixMode = SOURCE;
	
	// Prevent users from extending specific security/core classes
	public static var DISALLOW_OVERRIDE_CLASSES:Array<String> = [
		"states.PlayState",
		"online",
		"options",
		"online.states.DownloaderState",
		"states.MainMenuState", //this has lumod too
	];
}
