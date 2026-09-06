function smoke(out_dir)
%SMOKE  Call every wrapped function from MATLAB and check what comes back.
%   SMOKE(OUT_DIR) runs against the build in OUT_DIR, default `../out`.
%
%   Run `build_mex` in OUT_DIR first. Anything here that fails throws, so
%   `matlab -batch "smoke"` exits non-zero on a failure.
    arguments
        out_dir (1,1) string = fullfile(fileparts(mfilename('fullpath')), '..', 'out')
    end
    addpath(out_dir);
    cleanup = onCleanup(@() rmpath(out_dir));

    scalars();
    strings_and_cells();
    dictionaries();
    optionals();
    arrays();
    tuples();
    enums();
    errors();
    survives_clear_mex();
    exercises_release_paths();

    disp('boundary matlab smoke: OK');
end

function scalars()
    assert(boundary.str_len("wörld") == 6);   % 'ö' is 2 UTF-8 code units
    assert(boundary.count_strs({'a', 'bb'}) == 2);

    % An `arguments` block converts to the declared class before its
    % validators run, so an integer argument has to be declared `double`.
    % Declaring `int64` would round 2.5 to 3 and accept it.
    caught = false;
    try
        boundary.make_dict(2.5);
    catch err
        caught = true;
        assert(contains(err.identifier, 'validators') || ...
               contains(err.message, 'integer'), err.message);
    end
    assert(caught, 'make_dict(2.5) should be rejected, not rounded');
end

function strings_and_cells()
    assert(boundary.shout("héllo") == "HÉLLO");
    assert(isequal(boundary.upcase_strs({'ab', 'wörld'}), {'AB'; 'WÖRLD'}));

    % char, string array and cellstr are all natural ways to write this.
    assert(boundary.count_strs(["a", "bb", "ccc"]) == 3);
    assert(boundary.count_strs({}) == 0);
end

function dictionaries()
    total = boundary.sum_dict(struct('x', 1.5, 'y', 2.5));
    assert(total == 4.0);
    assert(boundary.sum_dict(struct('x', 1.5), scale = 2.0) == 3.0);

    d = boundary.make_dict(3);
    assert(isstruct(d));
    assert(d.k1 == 1.0 && d.k2 == 2.0 && d.k3 == 3.0);
end

function optionals()
    assert(boundary.maybe_sqrt(9.0) == 3.0);
    assert(isempty(boundary.maybe_sqrt([])));
    assert(isempty(boundary.maybe_sqrt(-1.0)));
end

function arrays()
    % A vector argument takes either orientation, and `[]` is a legal
    % empty vector.
    assert(isequal(boundary.scale_vec([1 2]), [2; 4]));
    assert(isequal(boundary.scale_vec([1; 2]), [2; 4]));
    assert(isempty(boundary.scale_vec([])));
    assert(isequal(boundary.scale_vec([1 2], factor = 3.0), [3; 6]));

    [cols, rows] = boundary.maximum_marginals([1 4; 3 2]);
    assert(isequal(cols, [3; 4]));
    assert(isequal(rows, [4; 3]));
end

function tuples()
    [x, n] = boundary.stats([1 2 3]);
    assert(isequal(x, [2; 4; 6]));
    assert(n == 3);

    % Fewer outputs than the declaration produces. Julia allocated both, so
    % the gateway has to release the one nobody asked for.
    only_x = boundary.stats([1 2 3]);
    assert(isequal(only_x, [2; 4; 6]));

    [shouted, words, lengths, mean_length] = boundary.bundle("a bb ccc");
    assert(shouted == "A BB CCC");
    assert(isequal(words, {'a'; 'bb'; 'ccc'}));
    assert(lengths.a == 1 && lengths.bb == 2 && lengths.ccc == 3);
    assert(mean_length == 2.0);

    % An absent optional inside a tuple.
    [~, ~, ~, empty_mean] = boundary.bundle("");
    assert(isempty(empty_mean));
end

function enums()
    % A member name or the underlying integer.
    assert(boundary.round_value(3.2) == 3.0);
    assert(boundary.round_value(3.7, mode = "round_down") == 3.0);
    assert(boundary.round_value(3.2, mode = "round_up") == 4.0);

    % A return comes back as its member name, which round-trips.
    assert(boundary.sign_mode(1.0) == "round_up");
    assert(boundary.round_value(3.2, mode = boundary.sign_mode(1.0)) == 4.0);
end

function errors()
    % The status code picks the identifier, so `ME.identifier` dispatch works.
    caught = false;
    try
        boundary.boom(7);
    catch err
        caught = true;
        assert(startsWith(err.identifier, 'jlw:'), err.identifier);
        assert(contains(err.message, 'boom 7'), err.message);
    end
    assert(caught, 'boom should raise');

    caught = false;
    try
        boundary.check_positive(-1.0);
    catch err
        caught = true;
        assert(contains(err.message, 'not positive'), err.message);
    end
    assert(caught, 'check_positive(-1) should raise');
end

function survives_clear_mex()
    % `clear mex` unloads the MEX file. The gateway keeps the library open,
    % so the next call reuses the running Julia rather than starting a second.
    assert(boundary.str_len("a") == 1);
    clear mex;
    assert(boundary.str_len("ab") == 2);
end

function exercises_release_paths()
    % Owning returns, an erroring call, and a tuple assigned to fewer
    % outputs than it declares. Each releases on a different path, and a
    % double free or a use-after-free shows up here as a crash. MATLAB
    % offers no portable way to read this process's memory, so growth
    % itself goes unchecked; run under valgrind to see that.
    for i = 1:2000
        boundary.upcase_strs({'x', 'y'});
        boundary.make_dict(5);
        boundary.scale_vec([1 2]);
        boundary.stats([1 2 3]);
        x = boundary.stats([1 2 3]); %#ok<NASGU>
        boundary.bundle("a bb");
        try
            boundary.boom(1);
        catch
        end
    end
end
