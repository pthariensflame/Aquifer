//
//  Basic.swift
//  Aquifer
//
//  Created by Alexander Ronald Altman on 1/28/15.
//  Copyright (c) 2015 TypeLift. All rights reserved.
//

// roughly `Pipes.Prelude`

import Swiftz

// MARK: - Data.Pipes

/// Returns a `Pipe` that produces the given value then terminates.
public func once<UO, UI, DI, DO, FR>(v : () -> FR) -> Proxy<UO, UI, DI, DO, FR> {
	return Proxy(ProxyRepr.Pure(v))
}

/// Returns a `Pipe` that discards all incoming values.
public func drain<UI, DI, DO, FR>() -> Proxy<(), UI, DI, DO, FR> {
	return for_(cat()) { discard($0) }
}

/// Returns a `Pipe` that applies a (side-effecting) action to all values flowing downstream.
public func chain<DT, FR>(action : DT -> Void) -> Pipe<DT, DT, FR>.T {
	return for_(cat()) { action($0); return yield($0) }
}

// MARK: - Data.Bool

/// Returns a `Pipe` that negates any `Bool`ean input flowing downstream.
public func not<FR>() -> Pipe<Bool, Bool, FR>.T {
	return map(!)
}

// MARK: - Data.Monoid

/// Folds the values inside the given pipe using the `Monoid` op.
public func mconcat<V : Monoid>(p : Producer<V, ()>.T) -> V {
	return fold(p, stepWith : { $0.op($1) }, initializeWith : V.mempty, extractWith : { $0 })
}

/// Mark: - Data.Foldable

/// Returns a representation of the given pipe as a list.
public func toList<V>(p : Producer<V, ()>.T) -> List<V> {
	return toListRepr(p.repr)
}

// MARK: - Data.List

// MARK: Basics

/// Returns the first element in the given pipe, if it exists.
public func head<V>(p : Producer<V, ()>.T) -> V? {
	switch next(p) {
	case .Left(_): return nil
	case let .Right(k): return k.0
	}
}

/// Returns the last element in the given pipe, if it exists.
public func last<V>(p : Producer<V, ()>.T) -> V? {
	switch next(p) {
	case .Left(_): return nil
	case let .Right((dO, q)):
		return lastInner(dO, q)
	}
}

/// Returns whether the given pipe has terminated.
public func isEmpty<V>(p : Producer<V, ()>.T) -> Bool {
	return next(p).isLeft
}

/// Counts the number of elements in the given pipe.
public func length<V>(p : Producer<V, ()>.T) -> Int {
	return fold(p, stepWith : { n, _ in n + 1 }, initializeWith : 0, extractWith : { $0 })
}

// MARK: Transformations

/// Returns a pipe that applies the given function to all values flowing downstream.
public func map<UI, DO, FR>(f : UI -> DO) -> Pipe<UI, DO, FR>.T {
	return for_(cat()) { v in yield(f(v)) }
}

/// Returns a pipe that uses the given function to produce sequences that are subsequently flattened
/// downstream.
public func mapMany<UI, S : SequenceType, FR>(f : UI -> S) -> Pipe<UI, S.Generator.Element, FR>.T {
	return for_(cat()) { each(f($0)) }
}

/// Returns a pipe that yields the description of each value flowing downstream.
public func description<UI : CustomStringConvertible, FR>() -> Pipe<UI, String, FR>.T {
	return map { $0.description }
}

/// Returns a pipe that yields the debug description of each value flowing downstream.
public func debugDescription<UI : CustomDebugStringConvertible, FR>() -> Pipe<UI, String, FR>.T {
	return map { $0.debugDescription }
}

// MARK: Folds

/// Folds over the elements of the given `Producer`.
public func fold<A, V, R>(p : Producer<V, ()>.T, stepWith step: (A, V) -> A, initializeWith initial: A, extractWith extractor: A -> R) -> R {
	return foldRepr(p.repr, stepWith : step, initializeWith : initial, extractWith : extractor)
}

/// A version of `fold` that preserve the return value of the given `Producer`.
public func foldRet<A, V, FR, R>(p : Producer<V, FR>.T, stepWith step: (A, V) -> A, initializeWith initial: A, extractWith extractor: A -> R) -> (R, FR) {
	return foldRetRepr(p.repr, stepWith : step, initializeWith : initial, extractWith : extractor)
}

// MARK: Special Folds

/// Returns a pipe that flattens the elements of any sequences flowing downstream.
public func concat<S : SequenceType, FR>() -> Pipe<S, S.Generator.Element, FR>.T {
	return for_(cat(), each)
}


/// Returns whether all elements of the receiver satisfy the given predicate.
public func all<V>(p : Producer<V, ()>.T, predicate : V -> Bool) -> Bool {
	return isEmpty(p >-> filter { !predicate($0) })
}

/// Returns whether any element of the receiver satisfies the given predicate.
public func any<V>(p : Producer<V, ()>.T, predicate : V -> Bool) -> Bool {
	return !isEmpty(p >-> filter(predicate))
}

/// Returns the conjunct of all values inside the pipe.
public func and(p : Producer<Bool, ()>.T) -> Bool {
	return all(p) { b in b }
}

/// Returns the disjunct of all values inside the pipe.
public func or(p : Producer<Bool, ()>.T) -> Bool {
	return any(p) { b in b }
}

/// Returns the sum of the values in the given pipe.
public func sum<V : NumericType>(p : Producer<V, ()>.T) -> V {
	return fold(p, stepWith : { $0.plus($1) }, initializeWith : V.zero, extractWith : { $0 })
}

/// Returns the product of the values in the given pipe.
public func product<V : NumericType>(p : Producer<V, ()>.T) -> V {
	return fold(p, stepWith : { $0.times($1) }, initializeWith : V.one, extractWith : { $0 })
}

/// Finds the maximum value among all the elements of the given pipe.
public func maximum<V : Comparable>(p : Producer<V, ()>.T) -> V? {
	func step(x : V?, _ v : V) -> V? {
		if let w = x {
			return max(v, w)
		} else {
			return x
		}
	}
	return fold(p, stepWith : step, initializeWith : nil, extractWith : { $0 })
}

/// Finds the minimum value among all the elements of the given pipe.
public func minimum<V : Comparable>(p : Producer<V, ()>.T) -> V? {
	func step(x : V?, _ v : V) -> V? {
		if let w = x {
			return min(v, w)
		} else {
			return x
		}
	}
	return fold(p, stepWith : step, initializeWith : nil, extractWith : { $0 })
}

// MARK: Scans

/// Returns a pipe that uses the given function as a left-scan on all values flowing downstream.
public func scan<A, UI, DO, FR>(stepWith step: (A, UI) -> A, initializeWith initial: A, extractWith extractor: A -> DO) -> Pipe<UI, DO, FR>.T {
	return yield(extractor(initial)) >>- { _ in await() >>- { scan(stepWith : step, initializeWith : step(initial, $0), extractWith : extractor) } }
}

// MARK: Infinite Pipes

/// Returns a pipe that always produces the given value.
public func repeat_<UO, UI, DO, FR>(v : () -> DO) -> Proxy<UO, UI, (), DO, FR> {
	return once(v) >~~ cat()
}

/// Returns a pipe that produces the given value a set amount of times.
public func replicate<UO, UI, DO>(v : () -> DO, n : Int) -> Proxy<UO, UI, (), DO, ()> {
	return once(v) >~~ take(n)
}

// MARK: Input Subsets

/// Returns a pipe that only allows a given number of values to pass through it.
public func take<DT>(n : Int) -> Proxy<(), DT, (), DT, ()> {
	if n <= 0 {
		return pure(())
	} else {
		return await() >>- { yield($0) >>- { _ in take(n - 1) } }
	}
}

/// Returns a pipe that only allows values to pass through it while the given predicate is true.
public func takeWhile<DT>(predicate : DT -> Bool) -> Proxy<(), DT, (), DT, ()> {
	return await() >>- { v in
		if predicate(v) {
			return yield(v) >>- { _ in takeWhile(predicate) }
		} else {
			return pure(())
		}
	}
}

/// Returns a `Pipe` that discards a given amount of values.
public func drop<DT, FR>(n : Int) -> Pipe<DT, DT, FR>.T {
	return dropInner(n) >>- { _ in cat() }
}

/// Returns a `Pipe` that discards values as long as the given predicate is true.
public func dropWhile<DT, FR>(predicate : DT -> Bool) -> Pipe<DT, DT, FR>.T {
	return await() >>- { v in
		if predicate(v) {
			return dropWhile(predicate)
		} else {
			return yield(v) >>- { _ in cat() }
		}
	}
}

// MARK: Searching with Equality

/// Returns whether a given value matches any of the values inside the given pipe.
public func elem<V : Equatable>(p : Producer<V, ()>.T, _ x : V) -> Bool {
	return any(p) { x == $0 }
}

/// Returns whether a given value does not match any of the values inside the given pipe.
public func notElem<V : Equatable>(p : Producer<V, ()>.T, _ x : V) -> Bool {
	return all(p) { x != $0 }
}

// MARK: Searching with Predicates

/// Finds the first element in the pipe that satisfies a given predicate.
public func find<V>(p : Producer<V, ()>.T, _ predicate : V -> Bool) -> V? {
	return head(p >-> filter(predicate))
}

/// Returns a `Pipe` that only forwards values that satisfy the given predicate.
public func filter<DT, FR>(predicate : DT -> Bool) -> Pipe<DT, DT, FR>.T {
	return for_(cat()) { v in
		if predicate(v) {
			return yield(v)
		} else {
			return pure(())
		}
	}
}

// MARK: Indexing

/// Returns a pipe that outputs the indices of all elements that match the given element
public func elemIndices<UI : Equatable, FR>(@autoclosure(escaping) x : () -> UI) -> Pipe<UI, Int, FR>.T {
	return findIndices { x() == $0 }
}

/// Finds the index of the first element in the pipe that satisfies a given predicate.
public func findIndex<V>(p : Producer<V, ()>.T, _ predicate : V -> Bool) -> Int? {
	return head(p >-> findIndices(predicate))
}

/// Returns a pipe that outputs the indices of all elements that match the given predicate.
public func findIndices<UI, FR>(predicate : UI -> Bool) -> Pipe<UI, Int, FR>.T {
	return findIndicesInner(predicate, 0)
}

// MARK: Zipping

/// Returns a `Producer` of pairs that zips the downstream output of the two given `Producer`s
/// together.
public func zip<V0, V1, R>(p : Producer<V0, R>.T, _ q : Producer<V1, R>.T) -> Producer<(V0, V1), R>.T {
	return zipWith(p, q) { ($0, $1) }
}

/// Returns a `Producer` of values that zips the downstream output of the two given pipes together
/// using the given function.
public func zipWith<V0, V1, V2, R>(p : Producer<V0, R>.T, _ q : Producer<V1, R>.T, _ f : (V0, V1) -> V2) -> Producer<V2, R>.T {
	switch next(p) {
	case let .Left(x): return pure(x)
	case let .Right((dO0, r)):
		switch next(q) {
		case let .Left(y): return pure(y)
		case let .Right((dO1, s)):
			return yield(f(dO0, dO1)) >>- { _ in zipWith(r, s, f) }
		}
	}
}

// this seems to required higher-kinded types to implement, even though none appear in its signature
//public func tee<A, R>(p : Consumer<A, R>.T) -> Pipe<A, A, R>.T {
//	let up : State<X, Optional<A>> = (tt >>- { ma in
//		switch ma {
//		case .None:
//			return pure(())
//		case .Some(let x):
//			return yield(x)
//		}
//	} >> await() >>- { a in
//		return put(.Some(a)) >> pure(a)
//	})
//	return up >>| (p |>> closed) >>- { r in
//		return get() >>- { ma in
//			switch ma {
//			case .None:
//				return pure(())
//			case .Some(let x):
//				return yield(x)
//			}
//		}
//		return pure(r)
//	}
//}

// this seems to required higher-kinded types to implement, even though none appear in its signature
/*public func generalize<UT, UI, DO, FR>(p : Pipe<UI, DO, FR>.T) -> Proxy<UT, UI, UT, DO, FR> {
}*/

// MARK: - Implementation Details Follow

private func dropInner<DT>(n : Int) -> Proxy<(), DT, (), DT, ()> {
	if n <= 0 {
		return pure(())
	} else {
		return await() >>- { _ in dropInner(n - 1) }
	}
}

private func findIndicesInner<UI, FR>(predicate : UI -> Bool, _ n : Int) -> Pipe<UI, Int, FR>.T {
	return await() >>- {
		if predicate($0) {
			return yield(n) >>- { _ in findIndicesInner(predicate, n + 1) }
		} else {
			return findIndicesInner(predicate, n + 1)
		}
	}
}

private func foldRepr<A, V, R>(p : ProxyRepr<X, (), (), V, ()>, stepWith step: (A, V) -> A, initializeWith initial: A, extractWith extractor: A -> R) -> R {
	switch p {
	case let .Request(uO, _): return closed(uO())
	case let .Respond(dO, fDI): return foldRepr(fDI(()), stepWith : step, initializeWith : step(initial, dO()), extractWith : extractor)
	case .Pure(_): return extractor(initial)
	}
}

private func foldRetRepr<A, V, FR, R>(p : ProxyRepr<X, (), (), V, FR>, stepWith step: (A, V) -> A, initializeWith initial: A, extractWith extractor: A -> R) -> (R, FR) {
	switch p {
	case let .Request(uO, _): return closed(uO())
	case let .Respond(dO, fDI): return foldRetRepr(fDI(()), stepWith : step, initializeWith : step(initial, dO()), extractWith : extractor)
	case let .Pure(x): return (extractor(initial), x())
	}
}

private func lastInner<V>(x : V, _ p : Producer<V, ()>.T) -> V? {
	switch next(p) {
	case .Left(_): return x
	case let .Right((dO, q)):
		return lastInner(dO, q)
	}
}

private func toListRepr<V>(p : ProxyRepr<X, (), (), V, ()>) -> List<V> {
	switch p {
	case let .Request(uO, _): return closed(uO())
	case let .Respond(dO, fDI): return List(dO(), toListRepr(fDI(())))
	case .Pure(_): return []
	}
}
