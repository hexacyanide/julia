debug = false

import Base.LinAlg
import Base.LinAlg: BlasComplex, BlasFloat, BlasReal

srand(1)

#Test equivalence of eigenvectors/singular vectors taking into account possible phase (sign) differences
function test_approx_eq_vecs{S<:Real,T<:Real}(a::StridedVecOrMat{S}, b::StridedVecOrMat{T}, error=nothing)
    n = size(a, 1)
    @test n==size(b,1) && size(a,2)==size(b,2)
    error==nothing && (error=n^3*(eps(S)+eps(T)))
    for i=1:n
        ev1, ev2 = a[:,i], b[:,i]
        deviation = min(abs(norm(ev1-ev2)),abs(norm(ev1+ev2)))
        if !isnan(deviation)
            @test_approx_eq_eps deviation 0.0 error
        end
    end
end

##############################
# Tests for special matrices #
##############################

n=12 #Size of matrix problem to test

debug && println("Bidiagonal matrices")
for relty in (Float32, Float64, BigFloat), elty in (relty, Complex{relty})
    debug && println("elty is $(elty), relty is $(relty)")
    dv = convert(Vector{elty}, randn(n))
    ev = convert(Vector{elty}, randn(n-1))
    b = convert(Matrix{elty}, randn(n, 2))
    if (elty <: Complex)
        dv += im*convert(Vector{elty}, randn(n))
        ev += im*convert(Vector{elty}, randn(n-1))
        b += im*convert(Matrix{elty}, randn(n, 2))
    end

    debug && println("Test upper and lower bidiagonal matrices")
    for isupper in (true, false)
        debug && println("isupper is: $(isupper)")
        T = Bidiagonal(dv, ev, isupper)

        @test size(T, 1) == size(T, 2) == n
        @test size(T) == (n, n)
        @test full(T) == diagm(dv) + diagm(ev, isupper?1:-1)
        @test Bidiagonal(full(T), isupper) == T
        z = zeros(elty, n)

        debug && println("Idempotent tests")
        for func in (conj, transpose, ctranspose)
            @test func(func(T)) == T
        end

        debug && println("Linear solver")
        Tfull = full(T)
        condT = cond(map(Complex128,Tfull))
        x = T \ b
        tx = Tfull \ b
        @test norm(x-tx,Inf) <= 4*condT*max(eps()*norm(tx,Inf), eps(relty)*norm(x,Inf))

        debug && println("Eigensystems")
        d1, v1 = eig(T)
        d2, v2 = eig(map(elty<:Complex ? Complex128 : Float64,Tfull))
        @test_approx_eq isupper?d1:reverse(d1) d2
        if elty <: Real
            test_approx_eq_vecs(v1, isupper?v2:v2[:,n:-1:1])
        end

        debug && println("Singular systems")
        if (elty <: BlasReal)
            @test_approx_eq svdvals(Tfull) svdvals(T)
            u1, d1, v1 = svd(Tfull)
            u2, d2, v2 = svd(T)
            @test_approx_eq d1 d2
            if elty <: Real
                test_approx_eq_vecs(u1, u2)
                test_approx_eq_vecs(v1, v2)
            end
            @test_approx_eq_eps 0 vecnorm(u2*diagm(d2)*v2'-Tfull) n*max(n^2*eps(relty), vecnorm(u1*diagm(d1)*v1' - Tfull))
            @inferred svdvals(T)
            @inferred svd(T)
        end

        debug && println("Binary operations")
        for isupper2 in (true, false)
            dv = convert(Vector{elty}, randn(n))
            ev = convert(Vector{elty}, randn(n-1))
            T2 = Bidiagonal(dv, ev, isupper2)
            Tfull2 = full(T2)
            for op in (+, -, *)
                @test_approx_eq full(op(T, T2)) op(Tfull, Tfull2)
            end
        end

        debug && println("Inverse")
        @test_approx_eq inv(T)*Tfull eye(n)
    end
end

debug && println("Diagonal matrices")
for relty in (Float32, Float64, BigFloat), elty in (relty, Complex{relty})
    debug && println("elty is $(elty), relty is $(relty)")
    d=convert(Vector{elty}, randn(n))
    v=convert(Vector{elty}, randn(n))
    U=convert(Matrix{elty}, randn(n,n))
    if elty <: Complex
        d+=im*convert(Vector{elty}, randn(n))
        v+=im*convert(Vector{elty}, randn(n))
        U+=im*convert(Matrix{elty}, randn(n,n))
    end
    D = Diagonal(d)
    DM = diagm(d)

    debug && println("Linear solve")
    @test_approx_eq_eps D*v DM*v n*eps(relty)*(elty<:Complex ? 2:1)
    @test_approx_eq_eps D*U DM*U n^2*eps(relty)*(elty<:Complex ? 2:1)
    if relty != BigFloat
        @test_approx_eq_eps D\v DM\v 2n^2*eps(relty)*(elty<:Complex ? 2:1)
        @test_approx_eq_eps D\U DM\U 2n^3*eps(relty)*(elty<:Complex ? 2:1)
    end

    debug && println("Simple unary functions")
    for func in (det, trace)
        @test_approx_eq_eps func(D) func(DM) n^2*eps(relty)*(elty<:Complex ? 2:1)
    end
    if relty <: BlasFloat
        for func in (expm,)
            @test_approx_eq_eps func(D) func(DM) n^3*eps(relty)
        end
    end
    if elty <: BlasComplex
        for func in (logdet, sqrtm)
            @test_approx_eq_eps func(D) func(DM) n^2*eps(relty)*2
        end
    end
    debug && println("Binary operations")
    d = convert(Vector{elty}, randn(n))
    D2 = Diagonal(d)
    DM2= diagm(d)
    for op in (+, -, *)
        @test_approx_eq full(op(D, D2)) op(DM, DM2)
    end

    #10036
    @test issym(D2)
    @test ishermitian(D2)
    if elty <: Complex
        dc = d + im*convert(Vector{elty}, ones(n))
        D3 = Diagonal(dc)
        @test issym(D3)
        @test !ishermitian(D3)
    end
end


debug && println("Test interconversion between special matrix types")
a=[1.0:n;]
A=Diagonal(a)
for newtype in [Diagonal, Bidiagonal, SymTridiagonal, Tridiagonal, LowerTriangular, UpperTriangular, Matrix]
    debug && println("newtype is $(newtype)")
    @test full(convert(newtype, A)) == full(A)
end

for isupper in (true, false)
    debug && println("isupper is $(isupper)")
    A=Bidiagonal(a, [1.0:n-1;], isupper)
    for newtype in [Bidiagonal, Tridiagonal, isupper ? UpperTriangular : LowerTriangular, Matrix]
        debug && println("newtype is $(newtype)")
        @test full(convert(newtype, A)) == full(A)
        @test full(newtype(A)) == full(A)
    end
    A=Bidiagonal(a, zeros(n-1), isupper) #morally Diagonal
    for newtype in [Diagonal, Bidiagonal, SymTridiagonal, Tridiagonal, isupper ? UpperTriangular : LowerTriangular, Matrix]
        debug && println("newtype is $(newtype)")
        @test full(convert(newtype, A)) == full(A)
        @test full(newtype(A)) == full(A)
    end
end

A = SymTridiagonal(a, [1.0:n-1;])
for newtype in [Tridiagonal, Matrix]
    @test full(convert(newtype, A)) == full(A)
end

A = Tridiagonal(zeros(n-1), [1.0:n;], zeros(n-1)) #morally Diagonal
for newtype in [Diagonal, Bidiagonal, SymTridiagonal, Matrix]
    @test full(convert(newtype, A)) == full(A)
end

A = LowerTriangular(full(Diagonal(a))) #morally Diagonal
for newtype in [Diagonal, Bidiagonal, SymTridiagonal, LowerTriangular, Matrix]
    @test full(convert(newtype, A)) == full(A)
end

# Test generic cholfact!
for elty in (Float32, Float64, Complex{Float32}, Complex{Float64})
    if elty <: Complex
        A = complex(randn(5,5), randn(5,5))
    else
        A = randn(5,5)
    end
    A = convert(Matrix{elty}, A'A)
    for ul in (:U, :L)
        @test_approx_eq full(cholfact(A, ul)[ul]) full(invoke(Base.LinAlg.chol!, (AbstractMatrix,Symbol),copy(A), ul))
    end
end

# Because transpose(x) == x
@test_throws ErrorException transpose(qrfact(randn(3,3)))
@test_throws ErrorException ctranspose(qrfact(randn(3,3)))
@test_throws ErrorException transpose(qrfact(randn(3,3), Val{false}))
@test_throws ErrorException ctranspose(qrfact(randn(3,3), Val{false}))
@test_throws ErrorException transpose(qrfact(big(randn(3,3))))
@test_throws ErrorException ctranspose(qrfact(big(randn(3,3))))
@test_throws ErrorException transpose(sub(sprandn(10, 10, 0.3), 1:4, 1:4))
@test_throws ErrorException ctranspose(sub(sprandn(10, 10, 0.3), 1:4, 1:4))

# test diag
A = eye(4)
@test diag(A) == ones(4)
@test diag(sub(A, 1:3, 1:3)) == ones(3)
