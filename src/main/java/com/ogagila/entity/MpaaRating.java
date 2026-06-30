package com.ogagila.entity;

import com.fasterxml.jackson.annotation.JsonValue;

/**
 * MPAA rating enum for film classification.
 * Maps to mpaa_rating enum type in openGauss.
 * Uses @JsonValue for proper serialization with custom display values.
 */
public enum MpaaRating {
    G("G"),
    PG("PG"),
    PG_13("PG-13"),
    R("R"),
    NC_17("NC-17");

    private final String value;

    MpaaRating(String value) {
        this.value = value;
    }

    @JsonValue
    public String getValue() {
        return value;
    }

    /**
     * Resolve an MpaaRating from its string representation.
     * Accepts both standard enum names (PG_13, NC_17) and display values (PG-13, NC-17).
     */
    public static MpaaRating fromValue(String v) {
        if (v == null || v.isEmpty()) {
            return null;
        }
        for (MpaaRating rating : MpaaRating.values()) {
            if (rating.value.equals(v) || rating.name().equals(v)) {
                return rating;
            }
        }
        throw new IllegalArgumentException("Unknown MpaaRating: " + v);
    }

    @Override
    public String toString() {
        return value;
    }
}
