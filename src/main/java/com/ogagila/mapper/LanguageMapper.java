package com.ogagila.mapper;

import com.ogagila.entity.Language;
import org.apache.ibatis.annotations.Param;

import java.util.List;

public interface LanguageMapper {

    List<Language> selectAll();

    Language selectById(@Param("languageId") Integer languageId);

    int insert(Language language);

    int update(Language language);
}
