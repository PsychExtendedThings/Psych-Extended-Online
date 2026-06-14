package backend;

import haxe.Json;
import haxe.xml.Access;
import objects.Character;

class Converters {
	/* --- CNE CONVERTERS --- */

	/**
	 * Converts a Codename Engine XML string to a Psych Engine JSON string.
	 * @param xmlString The raw XML string from the CNE character file.
	 * @param fallbackImagePath The path to the character image (e.g., "taeyai-dream").
	 * @return A formatted JSON string for PsychEngine.
	 */
	public static function parseCodenameChar(xmlString:String, fallbackImagePath:String = "my_character"):String {
		// Parse the XML
		var rawXml = Xml.parse(xmlString).firstElement();
		var xml = new Access(rawXml);
		var finalImagePath:String = xml.has.sprite ? 'characters/' + xml.att.sprite : 'characters/' + fallbackImagePath;

		var charFile:CharacterFile = {
			animations: [],
			image: finalImagePath,
			scale: xml.has.scale ? Std.parseFloat(xml.att.scale) : 1.0,
			sing_duration: xml.has.holdTime ? Std.parseFloat(xml.att.holdTime) : 4.0,
			healthicon: xml.has.icon ? xml.att.icon : fallbackImagePath,
			position: [
				xml.has.x ? Std.parseFloat(xml.att.x) : 0.0,
				xml.has.y ? Std.parseFloat(xml.att.y) : 0.0
			],
			camera_position: [
				xml.has.camx ? Std.parseFloat(xml.att.camx) : 0.0,
				xml.has.camy ? Std.parseFloat(xml.att.camy) : 0.0
			],
			flip_x: xml.has.flipX ? (xml.att.flipX == "true") : false,
			no_antialiasing: xml.has.antialiasing ? (xml.att.antialiasing == "false") : false,
			healthbar_colors: [161, 161, 161], // Default fallback color
			betterOffsets: true, // CNE like offset swapping feature
			codenameOffsets: false, // Fully CNE Offsetting for Codename Stages.
			isPlayer: xml.has.isPlayer ? (xml.att.isPlayer == "true") : false
		};
		if (PlayState.instance != null && PlayState.instance.stage != null)
			charFile.codenameOffsets = true;
		// Parse animations
		if (xml.hasNode.anim) {
			for (animNode in xml.nodes.anim) {
				// Parse indices array (e.g., "[1, 2, 3]" -> [1, 2, 3])
				var indicesArray:Array<Int> = [];
				if (animNode.has.indices) {
					var cleanString = StringTools.replace(animNode.att.indices, "[", "");
					cleanString = StringTools.replace(cleanString, "]", "");
					cleanString = StringTools.replace(cleanString, " ", ""); // Remove spaces
					
					if (cleanString.length > 0) {
						var strIndices = cleanString.split(",");
						for (i in strIndices) {
							indicesArray.push(Std.parseInt(i));
						}
					}
				}

				var offsetX:Int = animNode.has.x ? Std.parseInt(animNode.att.x) : 0;
				var offsetY:Int = animNode.has.y ? Std.parseInt(animNode.att.y) : 0;

				var animData:AnimArray = {
					anim: animNode.has.name ? animNode.att.name : "", // Psych 'anim' = CNE 'name'
					name: animNode.has.anim ? animNode.att.anim : "", // Psych 'name' = CNE 'anim'
					fps: animNode.has.fps ? Std.parseInt(animNode.att.fps) : 24,
					loop: animNode.has.loop ? (animNode.att.loop == "true") : false,
					indices: indicesArray,
					offsets: [offsetX, offsetY]
				};

				charFile.animations.push(animData);
			}
		}

		return Json.stringify(charFile, null, "\t");
	}

	// --- CONVERTION SETTINGS (`32, round, 5` is recommended) ---
	public static var sectionSnapping:Int = 32;
	public static var snappingMethod:String = "round"; 
	public static var sectionThreshold:Float = 5;
	// ----------------

	/**
	 * Converts CNE Chart and Meta Datas to PsychEngine JSON Format.
	 */
	public static function parseCodenameChart(chartData:Dynamic, metaData:Dynamic, ?isEvent:Bool):Dynamic
	{
		var curCamera:Dynamic = 0;
		var psychJson:Dynamic = {
			song: metaData.displayName,
			strumLines: [],
			notes: [],
			events: [],
			bpm: metaData.bpm,
			needsVoices: true,
			speed: chartData.scrollSpeed,
			player1: "bf",
			player2: "pico",
			gfVersion: "gf",
			stage: "stage"
		};
		if (metaData.displayName == null) psychJson.song = metaData.name;

		if (chartData.stage != null) psychJson.stage = chartData.stage;
		else if (metaData.stage != null) psychJson.stage = metaData.stage;

		var beatsPerMeasure:Dynamic = (metaData.beatsPerMeasure != null) ? metaData.beatsPerMeasure : 4;
		var stepsPerBeat:Dynamic = (metaData.stepsPerBeat != null) ? metaData.stepsPerBeat : 4;

		var curSpeed:Dynamic = chartData.scrollSpeed;
		var mustHit:Dynamic = false;
		var queueBPMChange:Dynamic = false;
		var curBPM:Dynamic = metaData.bpm;
		
		// FIX: Use explicit types for time math
		var songTime:Float = 0;
		var measureTimes:Array<Float> = [0];

		// FIX: Use explicit Array type
		var altEvents:Array<Array<Dynamic>> = [];
		if (chartData.strumLines != null) {
			for (i in 0...chartData.strumLines.length) {
				altEvents.push([{time: 0, anim: false, idle: false}]);
			}
		}

		// --- SECTION CREATION ---
		// FIX: Typed argument tilTime as Float
		var addSections = function(tilTime:Float) {
			if (songTime + sectionThreshold >= tilTime) return;
			var crochet:Dynamic = 60.0 / curBPM * 1000.0;
			var diff:Dynamic = tilTime - measureTimes[measureTimes.length - 1];
			var beats:Dynamic = diff / crochet;

			var targetBeats:Dynamic = beats / (4 / sectionSnapping);
			var snappedBeats:Dynamic = (snappingMethod == "round") ? Math.round(targetBeats) : Math.floor(targetBeats);
			beats = snappedBeats * (4 / sectionSnapping);
			var totalSections:Dynamic = Math.ceil(beats / beatsPerMeasure);

			for (i in 0...totalSections) {
				var secBeats:Dynamic = beatsPerMeasure;
				if (i == 0 && beats % beatsPerMeasure > 0) secBeats = beats % beatsPerMeasure;
				psychJson.notes.push({
					sectionNotes: [],
					sectionBeats: secBeats,
					mustHitSection: mustHit,
					targetCamera: curCamera,
					gfSection: false,
					bpm: curBPM,
					changeBPM: queueBPMChange,
					altAnim: false
				});
				queueBPMChange = false;
				songTime += secBeats * crochet;
				measureTimes.push(songTime);
			}
		};
		// --- EVENTS ---
		if (chartData.events != null) {
			// FIX: Cast to Array<Dynamic> for iteration
			var sortedEvents:Array<Dynamic> = chartData.events;
			sortedEvents.sort(function(ev1, ev2) return Math.floor(ev1.time - ev2.time));
			
			// FIX: Create a typed reference to the events array to avoid "Float should be Int" errors on length checks
			var eventsList:Array<Dynamic> = psychJson.events;

			for (event in sortedEvents) {
				switch (event.name) {
					case "Camera Movement":
						addSections(event.time);
						var strumId:Dynamic = event.params[0];
						if (chartData.strumLines != null && chartData.strumLines.length > strumId) {
							var charPosName:Dynamic = chartData.strumLines[strumId].position;
							if (charPosName == null) {
								var sType:Dynamic = chartData.strumLines[strumId].type;
								if (sType == 0) charPosName = "dad";
								else if (sType == 1) charPosName = "boyfriend";
								else if (sType == 2) charPosName = "girlfriend";
								else charPosName = "dad";
							}
							mustHit = (charPosName == "boyfriend");
						}
						curCamera = strumId;
						//omg it has own event now
						if (isEvent) {
							var psychEvent:Dynamic = ["Camera Movement", Std.string(strumId), ""];
							if (eventsList.length <= 0 || Math.abs(eventsList[eventsList.length - 1][0] - event.time) > 0.1)
								eventsList.push([event.time, [psychEvent]]);
							else
								eventsList[eventsList.length - 1][1].push(psychEvent);
						}
					case "BPM Change":
						addSections(event.time);
						curBPM = event.params[0];
						queueBPMChange = true;
					case "Add Camera Zoom":
						var psychEvent:Dynamic = ["Add Camera Zoom", event.params[0] * (event.params[1] == "camGame" ? 1 : 0), event.params[0] * (event.params[1] == "camHUD" ? 1 : 0)];
						// FIX: Use eventsList instead of psychJson.events for length checks
						if (eventsList.length <= 0 || Math.abs(eventsList[eventsList.length - 1][0] - event.time) > 0.1)
							eventsList.push([event.time, [psychEvent]]);
						else
							eventsList[eventsList.length - 1][1].push(psychEvent);
					case "Scroll Speed Change":
						if (curSpeed != event.params[1]) {
							// FIX: replaced 'json.meta.stepsPerBeat' with 'stepsPerBeat'
							var psychEvent:Dynamic = ["Change Scroll Speed", event.params[1] / curSpeed, event.params[2] / (60 / curBPM * 1000.0) * stepsPerBeat];
							curSpeed = event.params[1];
							if (eventsList.length <= 0 || Math.abs(eventsList[eventsList.length - 1][0] - event.time) > 0.1)
								eventsList.push([event.time, [psychEvent]]);
							else
								eventsList[eventsList.length - 1][1].push(psychEvent);
						}
					case "Play Animation":
						// FIX: replaced 'json.strumLines' with 'chartData.strumLines'
						try {
							var char:String = 'dad';
							switch (event.params[0]) {
								case 0: char = 'dad';
								case 1: char = 'bf';
								case 2: char = 'gf';
								default: char = 'none'; //should be done later
							}
							var psychEvent:Dynamic = ["Play Animation", event.params[1], char];
							if (eventsList.length <= 0 || Math.abs(eventsList[eventsList.length - 1][0] - event.time) > 0.1)
								eventsList.push([event.time, [psychEvent]]);
							else
								eventsList[eventsList.length - 1][1].push(psychEvent);
						} catch(e:Dynamic) {}
					case "Alt Animation Toggle":
						if (event.time == 0) {
							altEvents[event.params[2]][0].anim = event.params[0];
							altEvents[event.params[2]][1].idle = event.params[1];
							continue;
						}
						altEvents[event.params[2]].push({
							time: event.time,
							anim: event.params[0],
							idle: event.params[1]
						});
						var lastState:Dynamic = altEvents[event.params[2]][altEvents[event.params[2]].length - 2];
						if (lastState != null && lastState.idle != event.params[1]) {
							// FIX: replaced 'json.strumLines' with 'chartData.strumLines'
							var psychEvent:Dynamic = ["Alt Idle Animation", Std.string(chartData.strumLines[event.params[0]].type), (event.params[1]) ? "-alt" : ""];
							if (eventsList.length <= 0 || Math.abs(eventsList[eventsList.length - 1][0] - event.time) > 0.1)
								eventsList.push([event.time, [psychEvent]]);
							else
								eventsList[eventsList.length - 1][1].push(psychEvent);
						}
					default:
						var val1:Dynamic = "";
						var val2:Dynamic = "";
						if (event.params != null) {
							var mid:Dynamic = Math.ceil(event.params.length * 0.5);
							val1 = [for (i in 0...mid) Std.string(event.params[i])].join(", ");
							val2 = [for (i in mid...event.params.length) Std.string(event.params[i])].join(", ");
						}
						if (eventsList.length <= 0 || Math.abs(eventsList[eventsList.length - 1][0] - event.time) > 0.1)
							eventsList.push([event.time, [[event.name, val1, val2]]]);
						else
							eventsList[eventsList.length - 1][1].push([event.name, val1, val2]);
				}
			}
		}

		// Last section
		psychJson.notes.push({
			sectionNotes: [],
			sectionBeats: beatsPerMeasure,
			mustHitSection: mustHit,
			targetCamera: curCamera,
			gfSection: false,
			bpm: curBPM,
			changeBPM: queueBPMChange,
			altAnim: false
		});

		if (chartData.strumLines != null) {
			var numberThing:Dynamic = 2;
			// Counter for extra players (starts at 2 so first extra becomes 3)

			for (s in 0...chartData.strumLines.length) {
				var strum:Dynamic = chartData.strumLines[s];
				// --- Character Name Assignment based on Index ---
				if (strum.characters != null && strum.characters.length > 0) {
					switch (s) {
						case 0: psychJson.player2 = strum.characters[0];
						// Index 0 -> Dad (Player 2)
						case 1: psychJson.player1 = strum.characters[0];
						// Index 1 -> BF (Player 1)
						case 2: psychJson.gfVersion = strum.characters[0];
						// Index 2 -> GF
						// Extras (s > 2) names are not assigned to standard json fields
					}
				}

				var chars:Array<String> = [];
				if (strum.characters != null)
					chars = strum.characters;

				var strumLineData:Dynamic = {
					visible: strum.visible,
					characters: chars,
					cpu: (strum.type == 0 || strum.type == 2),
					type: strum.type
				};
				psychJson.strumLines.push(strumLineData);

				// FIX: Explicit typing for notes loop
				var strumNotes:Array<Dynamic> = strum.notes;
				strumNotes.sort(function(a, b) return Math.floor(a.time - b.time));

				var measureIndex:Int = 0;
				var altIndex:Int = 0;
				curBPM = metaData.bpm;
				songTime = 0;
				measureTimes = [0];

				switch (s) {
					case 0: // DAD (Opponent)
						for (note in strumNotes) {
							while (songTime <= note.time) {
								songTime += 60.0 / curBPM * 1000.0 * beatsPerMeasure;
								measureTimes.push(songTime);
							}
							while (measureIndex < measureTimes.length && measureTimes[measureIndex] <= note.time + sectionThreshold) measureIndex++;
							while (altEvents[s].length > altIndex && altEvents[s][altIndex].time <= note.time + sectionThreshold) altIndex++;

							var targetSecIdx:Dynamic = measureIndex - 1;
							if (targetSecIdx < 0) targetSecIdx = 0;
							if (targetSecIdx >= psychJson.notes.length) targetSecIdx = psychJson.notes.length - 1;
							var sec:Dynamic = psychJson.notes[targetSecIdx];
							var intFix:Dynamic = sec.mustHitSection ? 1 : 0;
							var psychNote:Dynamic = [note.time, note.id % 4, note.sLen];
							if (note.type != null && note.type > 0 && chartData.noteTypes != null) 
								psychNote.push(chartData.noteTypes[note.type]);
							if (altIndex > 0 && altEvents[s][altIndex - 1].anim) {
								if(psychNote.length < 4) psychNote.push("Alt Animation");
								else psychNote[3] = "Alt Animation";
							}
							//use new strumline id system for cne charts
							if(psychNote.length < 4) {
								psychNote.push(null);
								psychNote.push(s);
							} else {
								psychNote.push(s);
							}
							sec.sectionNotes.push(psychNote);
						}

					case 1: // BF (Player)
						for (note in strumNotes) {
							while (songTime <= note.time) {
								songTime += 60.0 / curBPM * 1000.0 * beatsPerMeasure;
								measureTimes.push(songTime);
							}
							while (measureIndex < measureTimes.length && measureTimes[measureIndex] <= note.time + sectionThreshold) measureIndex++;
							while (altEvents[s].length > altIndex && altEvents[s][altIndex].time <= note.time + sectionThreshold) altIndex++;

							var targetSecIdx:Dynamic = measureIndex - 1;
							if (targetSecIdx < 0) targetSecIdx = 0;
							if (targetSecIdx >= psychJson.notes.length) targetSecIdx = psychJson.notes.length - 1;
							var sec:Dynamic = psychJson.notes[targetSecIdx];
							var intFix:Dynamic = !sec.mustHitSection ? 1 : 0;
							var psychNote:Dynamic = [note.time, note.id % 4, note.sLen];
							if (note.type != null && note.type > 0 && chartData.noteTypes != null) 
								psychNote.push(chartData.noteTypes[note.type]);
							if (altIndex > 0 && altEvents[s][altIndex - 1].anim) {
								if(psychNote.length < 4) psychNote.push("Alt Animation");
								else psychNote[3] = "Alt Animation";
							}
							//use new strumline id system for cne charts
							if(psychNote.length < 4) {
								psychNote.push(null);
								psychNote.push(s);
							} else {
								psychNote.push(s);
							}
							sec.sectionNotes.push(psychNote);
						}

					case 2: // GF
						for (note in strumNotes) {
							while (songTime <= note.time) {
							   songTime += 60.0 / curBPM * 1000.0 * beatsPerMeasure;
								measureTimes.push(songTime);
							}
							while (measureIndex < measureTimes.length && measureTimes[measureIndex] <= note.time + sectionThreshold) measureIndex++;
							while (altEvents[s].length > altIndex && altEvents[s][altIndex].time <= note.time + sectionThreshold) altIndex++;

							var targetSecIdx:Dynamic = measureIndex - 1;
							if (targetSecIdx < 0) targetSecIdx = 0;
							if (targetSecIdx >= psychJson.notes.length) targetSecIdx = psychJson.notes.length - 1;
							var sec:Dynamic = psychJson.notes[targetSecIdx];
							var psychNote:Dynamic = [note.time, note.id % 4, note.sLen];
							if (note.type == 0) {
								// Added GF Sing for 0 type if desired, otherwise remove logic below to be pure ID
								psychNote.push("GF Sing");
							} else if (note.type > 0 && chartData.noteTypes != null) {
								psychNote.push("GF Sing: " + chartData.noteTypes[note.type]);
							}

							if (altIndex > 0 && altEvents[s][altIndex - 1].anim) {
								if(psychNote.length < 4) psychNote.push("Alt Animation");
								else psychNote[3] = "Alt Animation";
							}
							//use new strumline id system for cne charts
							if(psychNote.length < 4) {
								psychNote.push(null);
								psychNote.push(s);
							} else {
								psychNote.push(s);
							}
							sec.sectionNotes.push(psychNote);
						}

					default: // EXTRAS (Player 3, 4, 5...)
						numberThing++; 

						for (note in strumNotes) {
							while (songTime <= note.time) {
							   songTime += 60.0 / curBPM * 1000.0 * beatsPerMeasure;
								measureTimes.push(songTime);
							}
							while (measureIndex < measureTimes.length && measureTimes[measureIndex] <= note.time + sectionThreshold) measureIndex++;
							while (altEvents[s].length > altIndex && altEvents[s][altIndex].time <= note.time + sectionThreshold) altIndex++;

							var targetSecIdx:Dynamic = measureIndex - 1;
							if (targetSecIdx < 0) targetSecIdx = 0;
							if (targetSecIdx >= psychJson.notes.length) targetSecIdx = psychJson.notes.length - 1;
							var sec:Dynamic = psychJson.notes[targetSecIdx];
							var psychNote:Dynamic = [note.time, note.id % 4, note.sLen];
							// Only add note types if strictly necessary (from chart data), no generic "Player X Sing" bc multiple strums exists
							if (note.type != null && note.type > 0 && chartData.noteTypes != null) 
								psychNote.push(chartData.noteTypes[note.type]);
							if (altIndex > 0 && altEvents[s][altIndex - 1].anim) {
								if(psychNote.length < 4) psychNote.push("Alt Animation");
								else psychNote[3] = "Alt Animation";
							}
							//use new strumline id system for cne charts
							if(psychNote.length < 4) {
								psychNote.push(null);
								psychNote.push(s);
							} else {
								psychNote.push(s);
							}

							sec.sectionNotes.push(psychNote);
						}
				}
			}
		}

		var jsonOutput:Dynamic = {
			song: psychJson
		};

		return haxe.Json.stringify(jsonOutput, null, "\t");
	}
}
