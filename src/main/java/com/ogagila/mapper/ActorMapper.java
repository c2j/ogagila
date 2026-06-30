package com.ogagila.mapper;

import com.ogagila.entity.Actor;
import org.apache.ibatis.annotations.Param;

import java.util.List;

public interface ActorMapper {

    List<Actor> selectAll(@Param("offset") Integer offset, @Param("limit") Integer limit);

    int countAll();

    Actor selectById(@Param("actorId") Integer actorId);

    List<Actor> selectByName(@Param("name") String name);

    int insert(Actor actor);

    int update(Actor actor);

    int delete(@Param("actorId") Integer actorId);
}
