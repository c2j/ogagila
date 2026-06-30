package com.ogagila.service;

import com.ogagila.controller.api.dto.PageResult;
import com.ogagila.entity.Actor;
import com.ogagila.mapper.ActorMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@Transactional
public class ActorService {

    private final ActorMapper actorMapper;

    public ActorService(ActorMapper actorMapper) {
        this.actorMapper = actorMapper;
    }

    @Transactional(readOnly = true)
    public PageResult<Actor> getAll(int page, int size) {
        int offset = (page - 1) * size;
        List<Actor> actors = actorMapper.selectAll(offset, size);
        long total = actorMapper.countAll();
        return new PageResult<>(actors, total, page, size);
    }

    @Transactional(readOnly = true)
    public Actor getById(Integer actorId) {
        return actorMapper.selectById(actorId);
    }

    @Transactional(readOnly = true)
    public List<Actor> getByName(String name) {
        return actorMapper.selectByName(name);
    }

    public Actor create(Actor actor) {
        actorMapper.insert(actor);
        return actor;
    }

    public Actor update(Actor actor) {
        actorMapper.update(actor);
        return actor;
    }

    public void delete(Integer actorId) {
        actorMapper.delete(actorId);
    }
}
