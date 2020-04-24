########## Fake type-system


# Used to label all objects
struct VarRef
    parent::Union{VarRef,Nothing}
    name::Symbol
end
VarRef(m::Module) = VarRef((parentmodule(m) == Main || parentmodule(m) == m) ? nothing : VarRef(parentmodule(m)), nameof(m))

# These mirror Julia types (w/o the Fake prefix)
struct FakeTypeName
    name::VarRef
    parameters::Vector{Any}
end

function FakeTypeName(x; justname = false)
    if x isa DataType
        if justname
            FakeTypeName(VarRef(VarRef(x.name.module), x.name.name), [])
        else
            FakeTypeName(VarRef(VarRef(x.name.module), x.name.name), _parameter.(x.parameters))
        end
    elseif x isa Union
        FakeUnion(x)
    elseif x isa UnionAll
        FakeUnionAll(x)
    elseif x isa TypeVar
        FakeTypeVar(x)
    elseif x isa Core.TypeofBottom
        FakeTypeofBottom()
    else
        error((x, typeof(x)))
    end
end

struct FakeTypeofBottom end
struct FakeUnion
    a
    b
    FakeUnion(u::Union) = new(FakeTypeName(u.a, justname = true), FakeTypeName(u.b, justname = true))
end
struct FakeTypeVar
    name::Symbol
    lb
    ub
    FakeTypeVar(tv::TypeVar) = new(tv.name, FakeTypeName(tv.lb, justname = true), FakeTypeName(tv.ub, justname = true))
end
struct FakeUnionAll
    var::FakeTypeVar
    body::Any
    FakeUnionAll(ua::UnionAll) = new(FakeTypeVar(ua.var), FakeTypeName(ua.body, justname = true))
end

function _parameter(p::T) where T
    if p isa Union{Int,Symbol,Bool,Char}
        p
    elseif !(p isa Type) && isbitstype(T)
        0
    elseif p isa Tuple
        _parameter.(p)
    else
        FakeTypeName(p, justname = true)
    end
end

Base.print(io::IO, vr::VarRef) = vr.parent === nothing ? print(io, vr.name) : print(io, vr.parent, ".", vr.name)
function Base.print(io::IO, tn::FakeTypeName)
    print(io, tn.name)
    if !isempty(tn.parameters)
        print(io, "{")
        for i = 1:length(tn.parameters)
            print(io, tn.parameters[i])
            i != length(tn.parameters) && print(io, ",")
        end
        print(io, "}")
    end
end
Base.print(io::IO, x::FakeUnionAll) = print(io, x.body, " where ", x.var)
function Base.print(io::IO, x::FakeUnion; inunion = false)
    !inunion && print(io,  "Union{")
    print(io, x.a, ",")
    if x.b isa FakeUnion
        print(io, x.b, inunion = true)
    else
        print(io, x.b, "}")
    end
end
function Base.print(io::IO, x::FakeTypeVar)
    if isfakebottom(x.lb)
        if isfakeany(x.ub)
            print(io, x.name)
        else
            print(io, x.name,"<:",x.ub)
        end
    elseif isfakeany(x.ub)
        print(io, x.lb, "<:", x.name)
    else
        print(io, x.lb, "<:", x.name, "<:", x.ub)
    end
end

isfakeany(t) = false
isfakeany(t::FakeTypeName) = isfakeany(t.name)
isfakeany(vr::VarRef) = vr.name === :Any && vr.parent isa VarRef && vr.parent.name === :Core && vr.parent.parent === nothing

isfakebottom(t) = false
isfakebottom(t::FakeTypeofBottom) = true

function Base.:(==)(a::FakeTypeName, b::FakeTypeName)
    a.name == b.name && length(a.parameters) == length(b.parameters) || return false
    for i = 1:length(a.parameters)
        a.parameters[i] == b.parameters[i] || return false
    end
    return true
end
Base.:(==)(a::VarRef, b::VarRef) = a.parent == b.parent && a.name == b.name
Base.:(==)(a::FakeTypeVar, b::FakeTypeVar) = a.lb == b.lb && a.name == b.name && a.ub == b.ub
Base.:(==)(a::FakeUnionAll, b::FakeUnionAll) = a.var == b.var && a.body == b.body
Base.:(==)(a::FakeUnion, b::FakeUnion) = a.a == b.a && a.b == b.b
Base.:(==)(a::FakeTypeofBottom, b::FakeTypeofBottom) = true
