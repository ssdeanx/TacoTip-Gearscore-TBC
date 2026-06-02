function CastingBarMixin:OnEvent(event, ...)
	local arg1 = ...;

	local unit = self.unit;
	if ( event == "PLAYER_ENTERING_WORLD" ) then
		local nameChannel = UnitChannelInfo(unit);
		local nameSpell = UnitCastingInfo(unit);
		if ( nameChannel ) then
			event = "UNIT_SPELLCAST_CHANNEL_START";
			arg1 = unit;
		elseif ( nameSpell ) then
			event = "UNIT_SPELLCAST_START";
			arg1 = unit;
		else
			self:FinishSpell();
		end
	end

	if ( arg1 ~= unit ) then
		return;
	end

	if ( event == "UNIT_SPELLCAST_START" ) then
		local name, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible, spellID = UnitCastingInfo(unit);
		if ( not name or (not self.showTradeSkills and isTradeSkill)) then
			local desiredShowFalse = false;
			self:UpdateShownState(desiredShowFalse);
			return;
		end
		self.casting = true;
		self.castID = castID;
		self.channeling = nil;
		self.reverseChanneling = nil;
		self.spellID = spellID;
		self:UpdateShownState(self:ShouldShowCastBar());
	elseif ( event == "UNIT_SPELLCAST_STOP" ) then
		local _unit, castGUID, _spellID = ...;
		local complete = false;
		local interruptedBy = nil;
		self:HandleCastStop(event, castGUID, complete, interruptedBy);
	elseif ( event == "UNIT_SPELLCAST_CHANNEL_STOP" ) then
		local _unit, castGUID, _spellID, interruptedBy = ...;
		local complete = interruptedBy == nil;
		self:HandleCastStop(event, castGUID, complete, interruptedBy);
	elseif ( event == "UNIT_SPELLCAST_EMPOWER_STOP" ) then
		local _unit, castGUID, _spellID, complete, interruptedBy = ...;
		self:HandleCastStop(event, castGUID, complete, interruptedBy);
	elseif ( event == "UNIT_SPELLCAST_FAILED" ) then
		local _unit, castID, _spellID = ...
		local interruptedBy = nil;
		self:HandleInterruptOrSpellFailed(false, event, castID, interruptedBy);
	elseif ( event == "UNIT_SPELLCAST_INTERRUPTED" ) then
		local _unit, castID, _spellID, interruptedBy = ...
		self:HandleInterruptOrSpellFailed(false, event, castID, interruptedBy);
	elseif ( event == "UNIT_SPELLCAST_DELAYED" ) then
		if ( self:IsShown() ) then
			local name, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible = UnitCastingInfo(unit);
			if ( not name or (not self.showTradeSkills and isTradeSkill)) then
				local desiredShowFalse = false;
				self:UpdateShownState(desiredShowFalse);
				return;
			end
		end
	elseif ( event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_EMPOWER_START" ) then
		local name, text, texture, startTime, endTime, isTradeSkill, notInterruptible, spellID, _, numStages = UnitChannelInfo(unit);
		if ( not name or (not self.showTradeSkills and isTradeSkill)) then
			local desiredShowFalse = false;
			self:UpdateShownState(desiredShowFalse);
			return;
		end
	end
end
