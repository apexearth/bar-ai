/*
 * CircuitWDef.h
 *
 *  Created on: Oct 27, 2019
 *      Author: rlcevg
 */

#ifndef SRC_CIRCUIT_UNIT_CIRCUITWDEF_H_
#define SRC_CIRCUIT_UNIT_CIRCUITWDEF_H_

#include "WeaponDef.h"

namespace circuit {

class CWeaponDef {
public:
	using Id = int;

//	CWeaponDef(const CWeaponDef& that) = delete;
	CWeaponDef& operator=(const CWeaponDef&) = delete;
	CWeaponDef(springai::WeaponDef* def, springai::Resource* resM, springai::Resource* resE);
	virtual ~CWeaponDef();

	static Id WeaponIdFromLua(int luaId);

	springai::WeaponDef* GetDef() const { return def; }

	float GetRange() const { return range; }
	float GetAoe() const { return aoe; }
	float GetCostM() const { return costM; }
	float GetCostE() const { return costE; }
	float GetFireTime() const { return fireTime; }
	bool IsStockpile() const { return isStockpile; }
	bool IsHighTrajectory() const { return isHigh; }
	// apex: the shot's speed in elmos per second, and whether its kind can ever be side-stepped (a beam, a
	// lightning bolt, a hitscan rifle or a homing missile cannot; a shell, a rocket, a bomb or a D-gun ball can)
	float GetProjSpeed() const { return projSpeed; }
	bool IsDodgeable() const { return isDodgeable; }
	bool IsTurret() const { return isTurret; }  // apex: fires off its own facing (a fixed gun must face the target)

private:
	springai::WeaponDef* def;  // owner

	float range;
	float aoe;
	float costM;
	float costE;
	float fireTime;
	bool isStockpile : 1;
	bool isHigh : 1;
	bool isDodgeable : 1;
	bool isTurret : 1;
	float projSpeed;
};

} // namespace circuit

#endif // SRC_CIRCUIT_UNIT_CIRCUITWDEF_H_
