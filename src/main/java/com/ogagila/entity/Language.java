package com.ogagila.entity;

import java.time.OffsetDateTime;

/**
 * Entity mapping for language table.
 * Represents a language used for film dubbing/subtitling.
 */
public class Language {

    private Integer languageId;
    private String name;
    private OffsetDateTime lastUpdate;

    public Language() {
    }

    public Language(Integer languageId, String name, OffsetDateTime lastUpdate) {
        this.languageId = languageId;
        this.name = name;
        this.lastUpdate = lastUpdate;
    }

    public Integer getLanguageId() {
        return languageId;
    }

    public void setLanguageId(Integer languageId) {
        this.languageId = languageId;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public OffsetDateTime getLastUpdate() {
        return lastUpdate;
    }

    public void setLastUpdate(OffsetDateTime lastUpdate) {
        this.lastUpdate = lastUpdate;
    }

    @Override
    public String toString() {
        return "Language{" +
                "languageId=" + languageId +
                ", name='" + name + '\'' +
                ", lastUpdate=" + lastUpdate +
                '}';
    }
}
