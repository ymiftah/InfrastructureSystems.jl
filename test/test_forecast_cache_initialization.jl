@testset "ForecastCache sizes a single window" begin
    for in_memory in (false, true), virtual in (false, true)
        sys = IS.SystemData(; time_series_in_memory = in_memory)
        component = IS.TestComponent("cache-sizing", 1)
        IS.add_component!(sys, component)
        name = "bounded-sizing"
        resolution = Dates.Minute(5)
        start = Dates.DateTime("2026-01-01T04:05:00")
        horizon_count = 2
        if virtual
            timestamps = collect(range(start; step = resolution, length = 10))
            series = IS.SingleTimeSeries(
                name,
                TimeSeries.TimeArray(timestamps, Float64.(1:10)),
            )
            IS.add_time_series!(sys, component, series)
            IS.transform_single_time_series!(
                sys,
                IS.DeterministicSingleTimeSeries,
                horizon_count * resolution,
                resolution,
            )
        else
            data = SortedDict(
                time => Float64[i, i + 1] for
                (i, time) in enumerate(range(start; step = resolution, length = 9))
            )
            IS.add_time_series!(sys, component, IS.Deterministic(name, data, resolution))
        end

        for offset in (0, 3)
            initial_time = start + offset * resolution
            cache = IS.ForecastCache(
                IS.Deterministic,
                component,
                name;
                start_time = initial_time,
                cache_size_bytes = 2 * horizon_count * sizeof(Float64),
            )
            sample = IS._get_time_series(cache)
            @test IS.get_count(sample) == 1
            @test collect(IS.get_initial_times(sample)) == [initial_time]
            @test length(cache) == 9 - offset
            @test cache.in_memory_count == 2

            for i in 0:(8 - offset)
                timestamp = initial_time + i * resolution
                expected = Float64[offset + i + 1, offset + i + 2]
                actual = IS.get_time_series_array!(cache, timestamp)
                @test vec(TimeSeries.values(actual)) == expected
                repeated = IS.get_time_series_array!(cache, timestamp)
                @test TimeSeries.values(repeated) == TimeSeries.values(actual)
            end
            @test IS.get_next_time(cache) === nothing
        end
    end
end
