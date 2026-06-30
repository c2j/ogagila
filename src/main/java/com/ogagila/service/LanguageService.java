package com.ogagila.service;

import com.ogagila.entity.Language;
import com.ogagila.mapper.LanguageMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@Transactional
public class LanguageService {

    private final LanguageMapper languageMapper;

    public LanguageService(LanguageMapper languageMapper) {
        this.languageMapper = languageMapper;
    }

    @Transactional(readOnly = true)
    public List<Language> getAll() {
        return languageMapper.selectAll();
    }

    @Transactional(readOnly = true)
    public Language getById(Integer languageId) {
        return languageMapper.selectById(languageId);
    }

    public Language create(Language language) {
        languageMapper.insert(language);
        return language;
    }

    public Language update(Language language) {
        languageMapper.update(language);
        return language;
    }
}
