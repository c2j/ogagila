package com.ogagila.typehandler;

import com.ogagila.entity.MpaaRating;
import org.apache.ibatis.type.BaseTypeHandler;
import org.apache.ibatis.type.JdbcType;
import org.apache.ibatis.type.MappedTypes;

import java.sql.CallableStatement;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;

@MappedTypes(MpaaRating.class)
public class MpaaRatingTypeHandler extends BaseTypeHandler<MpaaRating> {

    @Override
    public void setNonNullParameter(PreparedStatement ps, int i, MpaaRating parameter, JdbcType jdbcType) throws SQLException {
        ps.setString(i, parameter.getValue());
    }

    @Override
    public MpaaRating getNullableResult(ResultSet rs, String columnName) throws SQLException {
        return MpaaRating.fromValue(rs.getString(columnName));
    }

    @Override
    public MpaaRating getNullableResult(ResultSet rs, int columnIndex) throws SQLException {
        return MpaaRating.fromValue(rs.getString(columnIndex));
    }

    @Override
    public MpaaRating getNullableResult(CallableStatement cs, int columnIndex) throws SQLException {
        return MpaaRating.fromValue(cs.getString(columnIndex));
    }
}
