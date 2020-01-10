(
	/*

	IEM MultiEncoder Dashboard

	This is a gui application for controlling the IEM MultiEncoder VST plugin for ambisonics.

	It contains different (simple) ways of positioning sources in 3D space by sending it's values to the targeted MultiEncoder via OSC.

	Each "target" section is modifyable via an LFO, this can either be one of the built in ones or it can be overwritten by setting a new source in \lfo key of the section in qustion, eg.

	g[\sections][0][\lfo].source = { LFDNoise.kr }

	TODO:
	- Sync between panels (but how???)
	- Controller input (should this be outside of the scope of this project?)

	KNOWN ISSUES:
	- You can set more than one section to control the same thing (one set to odd, another to all for example), this causes problems

	*/
	{ |numPanels=1, closeAble=false, numSrcs=16|
		// Gui object
		var panel, makePanel;
		var finalObjDict;

		makePanel = {|window, numTargetSections=4, defaultport=1234, panelNum|

			// Functions
			var sections;
			var makeParamSection, makeMainSection, makeLabel, makeAllSections, setActions, resetToCircle, scaleToParam, sendOsc, sendToSources, changeLfoSource, makeNodeProxies, makeOscFuncs, sendToSourceNum, resetSection, randomizeSection;

			var internalOscFunc;
			var objDict = IdentityDictionary.new;

			/* OSC */

			// Target OSC address
			objDict[\netaddr] = NetAddr.new("127.0.0.1",  defaultport);

			// Map from 0.0-1.0 to the parameter's min and max values
			scaleToParam = {|target, value, sourcenum, totalNumSrcs|
				switch(target,
					"elevation", {
						value.linlin(0.0,1.0,-180,180);
					},
					"azimuth", {
						// This slices the azimuth into slices of pizza: 
						// var minval = sourcenum/totalNumSrcs;
						// var maxval = sourcenum+1/totalNumSrcs;
						// value.linlin(0.0,1.0,minval,maxval).linlin(0.0,1.0,-180.0,180.0);

						value.linlin(0.0,1.0,-180,180);

					},
					"gain", {
						value.linlin(0.0,1.0,-60.0,10.0);
					}
				)
			};

			// Basic function to send data to the MultiEncoder instance
			sendOsc = {|target, sendVal, sourcenum, totalNumSrcs|
				// Map from 0.0-1.0 to the parameter's min and max values
				sendVal = scaleToParam.value(target, sendVal, sourcenum, totalNumSrcs);

				objDict[\netaddr].sendMsg("/MultiEncoder/%%".format(target, sourcenum), sendVal);
			};

			sendToSourceNum = {|inval=0.0, section, sourcenum|
				var modTarget = section[\modTarget].item;
				var selected = section[\selectedSources].item;
				var numSrcs = objDict[\main][\numSources].value.asInteger;
				var scale = section[\scales][sourcenum];
				var offset = section[\offsets][sourcenum];
				var sendVal = inval.wrap2(scale).linlin(0.0,1.0,offset,1.0);

				// Selection
				// TODO: Add more sorting functions here, like modulus, every 3rd, etc.
				switch(selected,
					"even", {
						// Add one to make the count start at 1 not 0
						(1+sourcenum).even.if{ sendOsc.value(modTarget, sendVal, sourcenum, numSrcs) }
					},
					"odd", {
						(1+sourcenum).odd.if{ sendOsc.value(modTarget, sendVal, sourcenum, numSrcs) }
					},
					"all", { 
						sendOsc.value(modTarget, sendVal, sourcenum, numSrcs) 
					}
				);
				// sendOsc.value(modTarget, sendVal, sourcenum, numSrcs) 
			};

			// lfo's data is picked up by this callback function
			makeOscFuncs = { |numProxies, sectionNum, section|
				var paths = numProxies.collect{|proxnum|
					"/reply/panel%_%_sec%_prox%".format(panelNum, "lfo", sectionNum, proxnum).asSymbol;
				};
				var of = numProxies.collect{|proxnum|
					OSCFunc({|msg ... args|
						var val = msg[3];
						val = val ? 0.0;
						{ sendToSourceNum.value(val, section, proxnum) }.defer // Defer is needed because otherwise thread issues arise, but cannot remember why
						// sendToSourceNum.value(val, section, proxnum)

					}, paths[proxnum])
				};

				// Callback for sending data from lfo to lang
				section[\internalOscPath] = paths;
				section[\oscFunc] = of;
			};

			internalOscFunc = { |section|
				OSCFunc({|msg ... args|
					var val = msg[3];
					sendToSources.value(val, section)
				}, section[\internalOscPath])
			};


			/* LFO */
			// TODO: MULTIPLE LFOS

			makeNodeProxies = {|numProxies, section|
				var np = numProxies.collect{
					NodeProxy.new(s, 'control', 1);
				};

				section[\lfo] = np;
			};

			changeLfoSource = {|lfotype="none", numSources, section|
				var sendMessageEvery = 0.05; // Seconds

				lfotype = if(lfotype.isNil, { "none" },{ lfotype });

				numSources.do{|sourcenum|
					var filter = {|in|
						SendReply.kr(
							Impulse.kr(sendMessageEvery.reciprocal), 
							cmdName: section[\internalOscPath][sourcenum], 
							values: in.linlin(-1.0,1.0,0.0,1.0)
						);
					};

					// Choose source function for node proxy
					var sourcefunc = switch(lfotype,
						"input", {
							// TODO
							{|input=0, scl=1| scl * A2K.kr(SoundIn.ar(input))};
						},
						"saw", {
							{|f=0| LFSaw.kr(f)};
						},
						"sine", { 
							{|f=0| SinOsc.kr(f)};
						},
						"tri", { 
							{|f=0| LFTri.kr(f)};
						},
						"random", {
							{|f=0| LFDNoise3.kr(f)};
						},
						"none", {
							// filter = {|in| in}; // Do not send OSC
							{|staticValue=0.0| DC.kr(staticValue.linlin(0.0,1.0,-1.0,1.0))}
						}
					);
					section[\lfo][sourcenum].source = sourcefunc;

					// Get init freq from freq multislider
					section[\lfo][sourcenum].set(\f, 
						section[\freqValueMultiSlider].value[sourcenum]
					);

					// Set osc callback as node proxy filter
					section[\lfo][sourcenum][1] = \filter -> filter;

				};

			};


			/* GUI */

			makeLabel = {|string| 
				StaticText(window).string_(string).font_(Font.defaultMonoFace)
			};

			// Create the top menu
			makeMainSection = {|addLayoutToDict|
				var thisData = IdentityDictionary.new;

				thisData[\numSources] = NumberBox(window)
				.clipLo_(1)
				.clipHi_(64)
				.decimals_(0)
				.value_(numSrcs);

				thisData[\targetPort] = NumberBox(window)
				.clipLo_(1)
				.clipHi_(9999)
				.decimals_(0)
				.value_(defaultport)
				.action_({ |obj| 
					objDict[\netaddr] = objDict[\netaddr].port_(obj.value.asInteger);
				});

				thisData[\resetBtn] = Button(window)
				.states_([["reset"]]);

				thisData[\randomizeBtn] = Button(window)
				.states_([["randomize"]]);

				thisData[\layout] = VLayout(

					makeLabel.("---------------------------------------"),
					HLayout(
						[makeLabel.("port"), s: 1],
						[thisData[\targetPort], s: 2],
						[makeLabel.("sources"), s: 1],
						[thisData[\numSources], s: 2],[nil, s:3],
						[StaticText(window).string_("Dashboard %".format(panelNum)).font_(Font.sansSerif(24)), s:5], [nil, s:1],
						[thisData[\randomizeBtn], s: 1], 
						[thisData[\resetBtn], s: 1], 
					),
				);

				addLayoutToDict.put(\main, thisData);

				thisData[\layout]
			};

			// Create section 
			makeParamSection = { |sectionNum|
				var thisData = IdentityDictionary.new;
				var numProxies = 64;

				// This nodeproxy will contain the lfo
				// thisData[\lfo] = NodeProxy.new(s, 'control', 1);
				makeNodeProxies.value(numProxies: numProxies, section: thisData);

				// thisData[\oscFunc] = internalOscFunc.value(thisData);
				makeOscFuncs.value(numProxies: numProxies, sectionNum: sectionNum, section: thisData);

				/* GUI OBJECTS */

				// thisData[\valueSlider] = Slider(window)
				// .orientation_(\horizontal);

				// 			thisData[\modSlider] = Slider(window)
				// 			.orientation_(\horizontal);

				thisData[\freqSlider] = Slider(window)
				.orientation_(\vertical)
				.value_(0.5);

				thisData[\scaleSlider] = Slider(window)
				.orientation_(\vertical)
				.value_(1.0);

				thisData[\offsetSlider] = Slider(window)
				.orientation_(\vertical)
				.value_(0.0);

				thisData[\modTarget] = PopUpMenu(window)
				.items_(["elevation", "azimuth", "gain"]);

				thisData[\selectedSources] = PopUpMenu(window)
				.items_(["all", "odd", "even"]);

				thisData[\modType] = PopUpMenu(window)
				.items_(["none", "saw", "tri", "sine", "random"/*, "input"*/]);

				thisData[\scaleValueMultiSlider] = MultiSliderView(window)
				.size_(numSrcs)
				.elasticMode_(1)
				.drawLines_(true)
				.thumbSize_(4)
				.value_(1.dup(numSrcs));

				thisData[\offsetValueMultiSlider] = MultiSliderView(window)
				.size_(numSrcs)
				.elasticMode_(1)
				.drawLines_(true)
				.thumbSize_(4)
				.value_(0.dup(numSrcs));

				thisData[\freqValueMultiSlider] = MultiSliderView(window)
				.size_(numSrcs)
				.elasticMode_(1)
				.drawLines_(true)
				.thumbSize_(4)
				.value_(0.5.dup(numSrcs));

				thisData[\layout] = VLayout(
					// makeLabel.("target " ++ sectionNum).font_(Font.sansSerif(20, true)),
					HLayout(
						[thisData[\selectedSources], s:1], 
						[thisData[\modTarget], s:1]
					),
					// HLayout(
					// 	[makeLabel.("value"), s: 1],
					// 	[thisData[\valueSlider], s: 2],
					// ),		
					HLayout(
						[makeLabel.("modtype"), s:1 ],
						[thisData[\modType], s: 2]
					),
					VLayout(
						[makeLabel.("freqs"), s:1 ],
						HLayout(
							[thisData[\freqValueMultiSlider], s: 13],
							[thisData[\freqSlider], s:1]
						)
					),
					VLayout(
						[makeLabel.("value scale"), s:1 ],
						HLayout(
							[thisData[\scaleValueMultiSlider], s: 13],
							[thisData[\scaleSlider], s:1]
						)
					),
					VLayout(
						[makeLabel.("value offsets"), s:1 ],
						HLayout(
							[thisData[\offsetValueMultiSlider], s: 13],
							[thisData[\offsetSlider], s:1]
						)
					)
				);

				thisData
			};

			// Make the appropriate amount of sections
			makeAllSections = {|numSects|
				objDict[\sections] = numSects.collect{|i|  
					makeParamSection.value(i) 
				};

				// Return the layout of the sections
				objDict[\sections].collect{|sect|
					sect[\layout]
				}
			};

			/* ACTIONS */
			resetSection = { |section, numsources|

				// section[\modTarget].valueAction_(0);
				// section[\selectedSources].valueAction_(0);
				section[\modType].valueAction_(0);

				section[\offsetSlider].valueAction_(0.0);
				section[\scaleSlider].valueAction_(1.0);
				section[\freqSlider].valueAction_(0.5);

				section[\scaleValueMultiSlider].valueAction_(1.0.dup(numsources));
				section[\offsetValueMultiSlider].valueAction_(0.0.dup(numsources));
				section[\freqValueMultiSlider].valueAction_(0.5.dup(numsources));
			};

			randomizeSection = { |section, numsources|
				var numTargets = section[\modTarget].items.size - 1;
				var numSourceSelections = section[\selectedSources].items.size - 1;
				var numModTypes = section[\modType].items.size - 1;

				// section[\modTarget].valueAction_(numTargets.rand);
				// section[\selectedSources].valueAction_(numSourceSelections.rand);
				section[\modType].valueAction_(numModTypes.rand);

				section[\offsetSlider].valueAction_(0.0);
				section[\scaleSlider].valueAction_(1.0);
				section[\freqSlider].valueAction_(0.5);

				section[\scaleValueMultiSlider].valueAction_(Array.rand(numsources, 0.7, 1.0));
				section[\offsetValueMultiSlider].valueAction_(Array.rand(numsources, 0.0, 0.75));
				section[\freqValueMultiSlider].valueAction_(Array.rand(numsources, 0.25, 1.0));
			};

			setActions = {
				// MAIN 

				// Randomize button 
				objDict[\main][\randomizeBtn].action_({
					var nums = objDict[\main][\numSources].value.asInteger;
					objDict[\sections].do{|section|
						randomizeSection.value(section, nums)	
					}
				});

				// Reset button
				objDict[\main][\resetBtn].action_({
					var nums = objDict[\main][\numSources].value.asInteger;
					objDict[\sections].do{|section|
						resetSection.value(section, nums)	
					}
				}
			);

			// OSC port of target
			objDict[\main][\targetPort].action_({|obj|
				objDict[\netaddr].port_(obj.value.asInteger);
			});

			// Number of sources in plugin
			objDict[\main][\numSources].action_({|obj| 
				var val = obj.value.asInteger;

				// Change number of sources in plugin
				objDict[\netaddr].sendMsg(
					"/MultiEncoder/inputSetting", val
				);

				// Update numbers of sliders in value scale multisliders
				objDict[\sections].do{ |section|
					{section[\scaleValueMultiSlider].size_(val).valueAction_(1.0.dup(val))}.defer;
					{section[\offsetValueMultiSlider].size_(val).valueAction_(0.0.dup(val))}.defer;
					{section[\freqValueMultiSlider].size_(val).valueAction_(0.5.dup(val))}.defer;
					{section[\modType].valueAction_(0)}.defer;
					{changeLfoSource.value(section[\modType].item, val, section)}.defer;
				}
			});

			// Section actions
			objDict[\sections].do{ |section|
				var numSources = objDict[\main][\numSources].value.asInteger;

				// Set the scale sliders
				section[\freqSlider].action_({|obj|
					{section[\freqValueMultiSlider].valueAction_(obj.value.dup(numSources))}.defer
				});

				section[\scaleSlider].action_({|obj|
					{section[\scaleValueMultiSlider].valueAction_(obj.value.dup(numSources))}.defer
				});

				section[\offsetSlider].action_({|obj|
					{section[\offsetValueMultiSlider].valueAction_(obj.value.dup(numSources))}.defer
				});

				// section[\modSlider].action_({|obj| 
				// 	var val = obj.value; 

				// 	section[\lfo].set(\f, val)
				// });

				section[\modType].action_({|obj|
					changeLfoSource.value(obj.item, numSources, section)
				});

				section[\modType].valueAction_(0);

				// section[\modTarget];
				// section[\selectedSources];
				section[\scaleValueMultiSlider].action_({|obj|
					section[\scales] = obj.value;
				}
			);

			section[\scales] = 1.0.dup(numSources);

			section[\offsetValueMultiSlider].action_({|obj|
				section[\offsets] = obj.value;

				section[\lfo].do{|lfo, lfonum| 
					lfo.set(\staticValue, section[\offsets][lfonum])	
				}
			}
		);

		section[\offsets] = 0.0.dup(numSources);

		section[\freqValueMultiSlider].action_({|obj|
			section[\freqs] = obj.value.linexp(0.0, 1.0, 0.0001, 3.0);

			section[\lfo].do{|lfo, lfonum| 
				lfo.set(\f, section[\freqs][lfonum])	
			}
		});

	section[\freqs] = 0.5.dup(numSources);
}
		};
		// Set up master layout combining the sections and the main section	
		objDict[\panelLayout] = VLayout(
			HLayout(
				*makeAllSections.value(4)
			),
			HLayout(
				makeMainSection.value(objDict),
			)
		);

		setActions.value();

		// Set defaults for all sections' targets
		objDict[\sections][0][\selectedSources].valueAction_(1);
		objDict[\sections][0][\modTarget].valueAction_(0);

		objDict[\sections][1][\selectedSources].valueAction_(2);
		objDict[\sections][1][\modTarget].valueAction_(0);

		objDict[\sections][2][\selectedSources].valueAction_(0);
		objDict[\sections][2][\modTarget].valueAction_(1);

		objDict[\sections][3][\selectedSources].valueAction_(0);
		objDict[\sections][3][\modTarget].valueAction_(2);

		objDict
	};

	s.waitForBoot{
		fork{
			var condition = Condition.new;

			s.sync;

			defer
			{finalObjDict = numPanels.collect{|panelNum|
				var thisPanel;
				var thisWindow = Window(
					"MultiEncoder Dashboard %".format(panelNum), 
					bounds: Rect(0,0,1000,200)
				)
				.front
				.userCanClose_(closeAble);

				thisPanel = makePanel.value(thisWindow, defaultport: 1234+panelNum, panelNum: panelNum);

				thisWindow.layout = thisPanel[\panelLayout];

				if((panelNum+1) == numPanels, { condition.unhang });

				thisPanel;

			};

		};
		
			condition.hang;

			{MultiEncoderDashboard.addDashboard(finalObjDict)}.defer;
			// finalObjDict;

		}
	}
}
)
