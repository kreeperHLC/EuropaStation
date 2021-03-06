#define ORE_DISABLED 0
#define ORE_SMELT    1
#define ORE_COMPRESS 2
#define ORE_ALLOY    3

/obj/machinery/mineral/processing_unit
	name = "mineral processor"
	icon_state = "furnace"
	light_power = 3
	light_range = 3
	light_color = COLOR_ORANGE
	console = /obj/machinery/computer/mining

	var/sheets_per_tick = 10
	var/list/ores_processing
	var/list/ores_stored
	var/report_all_ores
	var/active = FALSE

/obj/machinery/mineral/processing_unit/Initialize()
	. = ..()
	ores_processing = list()
	ores_stored = list()
	for(var/orename in SSmaterials.processable_ores)
		ores_processing[orename] = 0
		ores_stored[orename] = 0

/obj/machinery/mineral/processing_unit/process()

	if(!active) return

	//Grab some more ore to process this tick.
	if(input_turf)
		for(var/obj/item/I in recursive_content_check(input_turf, sight_check = FALSE, include_mobs = FALSE))
			if(QDELETED(I) || !I.simulated || I.anchored)
				continue
			if(LAZYLEN(I.matter))
				for(var/o_material in I.matter)
					if(!isnull(ores_stored[o_material]))
						ores_stored[o_material] += I.matter[o_material]
			qdel(I)
			CHECK_TICK

	//Process our stored ores and spit out sheets.
	if(output_turf)
		var/sheets = 0
		var/list/attempt_to_alloy = list()
		for(var/metal in ores_stored)

			if(sheets >= sheets_per_tick)
				break

			if(ores_stored[metal] <= 0 || ores_processing[metal] == ORE_DISABLED)
				continue

			var/material/M = SSmaterials.get_material(metal)
			var/result = 0

			var/ore_mode = ores_processing[metal]
			if(ore_mode == ORE_ALLOY)
				if(SSmaterials.alloy_components[metal])
					attempt_to_alloy[metal] = TRUE
				else
					result = min(sheets_per_tick - sheets, Floor(ores_processing[metal] / M.units_per_sheet))
					ores_processing[metal] -= result * M.units_per_sheet
					result = -(result)
			else if(ore_mode == ORE_COMPRESS)
				result = attempt_compression(M, sheets_per_tick - sheets)
			else if(ore_mode == ORE_SMELT)
				result = attempt_smelt(M, sheets_per_tick - sheets)

			sheets += abs(result)
			while(result < 0)
				new /obj/item/ore(output_turf, MATERIAL_WASTE)
				result++

		// Try to make any available alloys.
		if(attempt_to_alloy.len)

			var/list/making_alloys = list()
			for(var/thing in SSmaterials.alloy_products)
				var/material/M = thing
				var/failed = FALSE
				for(var/otherthing in M.composite_material)
					if(!attempt_to_alloy[otherthing] || ores_stored[otherthing] < M.composite_material[otherthing])
						failed = TRUE
						break
				if(!failed) making_alloys += M

			for(var/thing in making_alloys)
				if(sheets >= sheets_per_tick) break
				var/material/M = thing
				var/making = 0
				for(var/otherthing in M.composite_material)
					making = Floor(ores_stored[otherthing] / M.composite_material[otherthing])
				making = min(sheets_per_tick-sheets, making)
				for(var/otherthing in M.composite_material)
					ores_stored[otherthing] -= making * M.composite_material[otherthing]
				new M.stack_type(output_turf, amount = max(1, making))

/obj/machinery/mineral/processing_unit/proc/attempt_smelt(var/material/metal, var/max_result)
	. = Clamp(Floor(ores_stored[metal.name]/metal.units_per_sheet),1,max_result)
	ores_stored[metal.name] -= . * metal.units_per_sheet
	var/material/M = SSmaterials.get_material(metal.ore_smelts_to)
	if(istype(M))
		new M.stack_type(output_turf, amount = .)
	else
		. = -(.)

/obj/machinery/mineral/processing_unit/proc/attempt_compression(var/material/metal, var/max_result)
	var/making = Clamp(Floor(ores_stored[metal.name]/metal.units_per_sheet),1,max_result)
	if(making >= 2)
		ores_stored[metal.name] -= making * metal.units_per_sheet
		. = Floor(making * 0.5)
		var/material/M = SSmaterials.get_material(metal.ore_compresses_to)
		if(istype(M))
			new M.stack_type(output_turf, amount = .)
		else
			. = -(.)
	else
		. = 0

/obj/machinery/mineral/processing_unit/get_console_data()
	. = ..()
	for(var/ore in ores_processing)
		if(!ores_stored[ore] && !report_all_ores) continue
		var/material/M = SSmaterials.get_material(ore)
		var/line = "=== [Floor(ores_stored[ore] / M.units_per_sheet)] x [capitalize(M.display_name)] ([ores_stored[ore]]u) "
		while(length(line) < 30) line += "="
		if(ores_processing[ore])
			switch(ores_processing[ore])
				if(ORE_DISABLED)
					line = "[line] <font color='red'>not processing</font> "
				if(ORE_SMELT)
					line = "[line] <font color='orange'>smelting</font> "
				if(ORE_COMPRESS)
					line = "[line] <font color='blue'>compressing</font> "
				if(ORE_ALLOY)
					line = "[line] <font color='gray'>alloying</font> "
		else
			line = "[line] <font color='red'>not processing</font> "
		while(length(line) < 50) line += "="
		. += "[line] <a href='?src=\ref[src];toggle_smelting=[ore]'>\[change\]</a>"
	. += "Currently displaying [report_all_ores ? "all ore types" : "only available ore types"]. <A href='?src=\ref[src];toggle_ores=1'>\[[report_all_ores ? "show less" : "show more"]\]</a>"
	. += "The ore processor is currently <A href='?src=\ref[src];toggle_power=1'>[(active ? "<font color='green'>processing</font>" : "<font color='red'>disabled</font>")]</a>."

/obj/machinery/mineral/processing_unit/Topic(href, href_list)
	. = ..()
	if(can_use(usr))
		if(href_list["toggle_smelting"])
			var/choice = input("What setting do you wish to use for processing [href_list["toggle_smelting"]]?") as null|anything in list("Smelting","Compressing","Alloying","Nothing")
			if(!choice) return
			switch(choice)
				if("Nothing")     choice = ORE_DISABLED
				if("Smelting")    choice = ORE_SMELT
				if("Compressing") choice = ORE_COMPRESS
				if("Alloying")    choice = ORE_ALLOY
			ores_processing[href_list["toggle_smelting"]] = choice
			. = TRUE
		else if(href_list["toggle_power"])
			active = !active
			. = TRUE
		else if(href_list["toggle_ores"])
			report_all_ores = !report_all_ores
			. = TRUE
		if(. && console)
			console.updateUsrDialog()

#undef ORE_DISABLED
#undef ORE_SMELT
#undef ORE_COMPRESS
#undef ORE_ALLOY
