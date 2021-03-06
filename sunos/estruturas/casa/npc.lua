--[[
	Mod Sunos para Minetest
	Copyright (C) 2017 BrunoMine (https://github.com/BrunoMine)
	
	Recebeste uma cópia da GNU Lesser General
	Public License junto com esse software,
	se não, veja em <http://www.gnu.org/licenses/>. 
	
	NPC das casas
  ]]

-- Cronograma de atividades do NPC da casa (carregamento de script)
dofile(minetest.get_modpath("sunos").."/estruturas/casa/cronograma_npc.lua") 

-- Tradução de strings
local S = sunos.S

-- Envia uma formspec simples de aviso
local avisar = function(player, texto)
	if not player then
		minetest.log("error", "[Sunos] player nulo (em avisar do script interface.lua)")
		return false
	end
	if not texto then
		minetest.log("error", "[Sunos] texto nulo (em avisar do script interface.lua)")
		return false
	end
	
	minetest.show_formspec(player:get_player_name(), "sunos:npc", "size[12,1]"
		..default.gui_bg
		..default.gui_bg_img
		.."label[0.5,0;"..S("Aviso").." \n"..texto.."]")
	return true
end

-- Nodes andaveis para os NPC caseiros
sunos.estruturas.casa.walkable_nodes = {
	"sunos:carpete_palha",
	"sunos:carpete_palha_nodrop",
	"sunos:torch_nodrop",
	"sunos:torch_ceiling_nodrop",
	"sunos:torch_wall_nodrop"
}

-- Busca todos os nodes de um determinada lista de tipos na casa
local pegar_nodes_casa = function(pos, dist, nodes)
	return minetest.find_nodes_in_area(
		{x=pos.x-dist, y=pos.y, z=pos.z-dist}, 
		{x=pos.x+dist, y=pos.y+14, z=pos.z+dist}, 
		nodes)
end

-- Configurar lugares do npc
local set_npc_places = function(self)
	local pf = self.sunos_fundamento
	if not pf then return end
	local dist = minetest.get_meta(pf):get_string("dist")
	
	-- Bau
	do
		local bau = sunos.copy_tb(self.mypos)
		local v = minetest.facedir_to_dir(minetest.get_node(bau).param2)
		local acesso = vector.subtract(bau, v)
		npc.places.add_shared(self, "bau_primario", "bau", bau, acesso)
	end
	
	-- Cama
	local camas = pegar_nodes_casa(pf, dist, {"beds:bed_bottom"})
	if camas[1] then
		local cama = camas[1]
		local v = minetest.facedir_to_dir(minetest.get_node(cama).param2)
		local acesso = vector.subtract(cama, v)
		npc.places.add_owned(self, "cama_1", "bed_primary", cama, acesso)
	end
	
	-- Interior e exterior da casa
	local portas = pegar_nodes_casa(pf, dist, {"doors:door_wood_a"})
	if portas[1] then
		local porta = portas[1]
		local v = minetest.facedir_to_dir(minetest.get_node(porta).param2)
		local dentro = vector.subtract(porta, v)
		local fora = vector.add(porta, v)
		npc.places.add_shared(self, "casa_dentro_1", "home_inside", dentro, nil)
		npc.places.add_shared(self, "casa_fora_1", "home_outside", fora, nil)
	end
	
	local nodes
	
	-- Forno
	nodes = pegar_nodes_casa(pf, dist, {"default:furnace"})
	for n,node in ipairs(nodes) do
		local v = minetest.facedir_to_dir(minetest.get_node(node).param2)
		local acesso = vector.subtract(node, v)
		if n == 1 then
			npc.places.add_owned(self, "forno_1", "furnace_primary", node, acesso)
		else
			npc.places.add_shared(self, "forno_"..n, "furnace_shared", node, acesso)
		end
	end
	
	-- Compostagens
	nodes = pegar_nodes_casa(pf, dist, {"sunos:wood_barrel_nodrop"})
	for n,node in ipairs(nodes) do
		local v = minetest.facedir_to_dir(minetest.get_node(node).param2)
		local acesso = vector.subtract(node, v)
		npc.places.add_shared(self, "compostagem_"..n, "compostagem", node, acesso)
	end
	
	-- Tear
	nodes = pegar_nodes_casa(pf, dist, {"sunos:tear_palha_nodrop"})
	for n,node in ipairs(nodes) do
		local v = minetest.facedir_to_dir(minetest.get_node(node).param2)
		local acesso = vector.subtract(node, v)
		acesso.y = acesso.y-1
		npc.places.add_shared(self, "tear_"..n, "tear", node, acesso)
	end
	
	-- Bancada de Trabalho
	nodes = pegar_nodes_casa(pf, dist, {"sunos:bancada_de_trabalho_nodrop"})
	for n,node in ipairs(nodes) do
		local v = minetest.facedir_to_dir(minetest.get_node(node).param2)
		local acesso = vector.subtract(node, v)
		npc.places.add_shared(self, "bancada_de_trabalho_"..n, "bancada_de_trabalho", node, acesso)
	end
	
	-- Kit culinario
	nodes = pegar_nodes_casa(pf, dist, {"sunos:kit_culinario_nodrop"})
	for n,node in ipairs(nodes) do
		local v = minetest.facedir_to_dir(minetest.get_node(node).param2)
		local acesso = vector.subtract(node, v)
		acesso.y = acesso.y-1
		npc.places.add_shared(self, "kit_culinario_"..n, "kit_culinario", node, acesso)
	end
end

-- Criar entidade NPC
sunos.npcs.npc.registrar("caseiro", {
	max_dist = 100,	
	node_spawner = "sunos:bau_casa",
	
	after_activate = function(self)
		-- Corrige animação se estiver durmindo (sempre para a cama primaria)
		if self.actions.move_state.is_laying == true then
			local target = sunos.copy_tb(npc.places.get_by_type(self, "bed_primary")[1])
			npc.add_task(self, npc.actions.cmd.USE_BED, 
				{
					pos = "bed_primary",
					action = npc.actions.const.beds.LAY
				}
			)
			npc.add_action(self, npc.actions.cmd.FREEZE, {freeze = true})
		end
		
		local meta = minetest.get_meta(self.mypos)
		
		-- Verifica se ja tem roteiro salvo em si mesmo
		if self.data_roteiro 
			and self.roteiro
			-- Está dentro do periodo de validade do roteiro
			and self.data_roteiro + 2 >= minetest.get_day_count() 
		then
			-- Reatribui agenda de tarefas
			sunos.estruturas.casa.atribuir_cronograma_npc(self, self.roteiro, self.data_roteiro)
		
		
		-- Verifica se o bau proprio tem roteiro
		elseif meta:get_string("roteiro") ~= ""
			and meta:get_string("data_roteiro") ~= ""
			-- Está dentro do periodo de validade do roteiro
			and tonumber(meta:get_string("data_roteiro")) + 2 >= minetest.get_day_count() 
		then			
			-- Reatribui agenda de tarefas
			sunos.estruturas.casa.atribuir_cronograma_npc(self, meta:get_string("roteiro"), meta:get_string("data_roteiro"))
		
		
		else
			-- Cria nova agenda de tarefas
			sunos.estruturas.casa.atribuir_cronograma_npc(self)
		end
		
		-- Configurar lugares
		set_npc_places(self)
	end,
	
	drops = {
		{name = "default:apple", chance = 2, min = 1, max = 2},
	},
})


