// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface ILegionMetadataStore {
    struct LegionMetadata {
        LegionGeneration legionGeneration;
        LegionClass legionClass;
        LegionRarity legionRarity;
        uint8 questLevel;
        uint8 craftLevel;
        uint8[6] constellationRanks;
    }

    enum Constellation {
        FIRE,
        EARTH,
        WIND,
        WATER,
        LIGHT,
        DARK
    }

    enum LegionRarity {
        LEGENDARY,
        RARE,
        SPECIAL,
        UNCOMMON,
        COMMON,
        RECRUIT
    }

    enum LegionClass {
        RECRUIT,
        SIEGE,
        FIGHTER,
        ASSASSIN,
        RANGED,
        SPELLCASTER,
        RIVERMAN,
        NUMERAIRE,
        ALL_CLASS,
        ORIGIN
    }

    enum LegionGeneration {
        GENESIS,
        AUXILIARY,
        RECRUIT
    }

    // Sets the intial metadata for a token id.
    // Admin only.
    function setInitialMetadataForLegion(address _owner, uint256 _tokenId, LegionGeneration _generation, LegionClass _class, LegionRarity _rarity) external;

    // Increases the quest level by one. It is up to the calling contract to regulate the max quest level. No validation.
    // Admin only.
    function increaseQuestLevel(uint256 _tokenId) external;

    // Increases the craft level by one. It is up to the calling contract to regulate the max craft level. No validation.
    // Admin only.
    function increaseCraftLevel(uint256 _tokenId) external;

    // Increases the rank of the given constellation to the given number. It is up to the calling contract to regulate the max constellation rank. No validation.
    // Admin only.
    function increaseConstellationRank(uint256 _tokenId, Constellation _constellation, uint8 _to) external;

    // Returns the metadata for the given legion.
    function metadataForLegion(uint256 _tokenId) external view returns(LegionMetadata memory);
}
