/*
 * Copyright (c) 2022 NVIDIA Corporation
 *
 * Licensed under the Apache License Version 2.0 with LLVM Exceptions
 * (the "License"); you may not use this file except in compliance with
 * the License. You may obtain a copy of the License at
 *
 *   https://llvm.org/LICENSE.txt
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#pragma once

#include <execution.hpp>
#include <type_traits>

#include "common.cuh"

namespace example::cuda::stream {
  namespace let_xxx {
    template <class Fun, class ResultSenderT, class... As>
      __launch_bounds__(1)
      __global__ void kernel_with_result(Fun fn, ResultSenderT* result, As&&... as) {
        new (result) ResultSenderT(fn((As&&)as...));
      }

    template <class... _Ts>
      struct __as_tuple {
        _P2300::execution::__decayed_tuple<_Ts...> operator()(_Ts...) const;
      };

    template <class... Sizes>
      struct max_in_pack {
        static constexpr std::size_t value = std::max({std::size_t{}, _P2300::__v<Sizes>...});
      };

    template <class _SenderId, class _ReceiverId, class _FunId, class _Let>
      struct __receiver;

    template <class... _Ts>
      struct __which_tuple_ : _Ts... {
        using _Ts::operator()...;
      };

    struct __which_tuple_base {
      template <class... _Ts>
        _P2300::execution::__decayed_tuple<_Ts...> operator()(_Ts&&...) const;
    };

    template <std::execution::sender, class, class>
      struct __which_tuple : __which_tuple_base {};

    template <class _Sender, class _Env>
        requires std::execution::sender<_Sender, _Env>
      struct __which_tuple<_Sender, _Env, std::execution::set_value_t>
        : std::execution::value_types_of_t<_Sender, _Env, __as_tuple, __which_tuple_> {};

    template <class _Sender, class _Env>
        requires std::execution::sender<_Sender, _Env>
      struct __which_tuple<_Sender, _Env, std::execution::set_error_t>
        : _P2300::execution::__error_types_of_t<
            _Sender,
            _Env,
            _P2300::__transform<_P2300::__q<__as_tuple>, _P2300::__q<__which_tuple_>>> {};

    template <class _Fun>
      struct __applyable_fn {
        template <class... _As>
          _P2300::__ operator()(_As&&...) const;

        template <class... _As>
            requires std::invocable<_Fun, _As...>
          std::invoke_result_t<_Fun, _As...> operator()(_As&&...) const {
            std::terminate(); // this is never called; but we need a body
          }
      };

    template <class _Fun, class _Tuple>
      concept __applyable =
        requires (__applyable_fn<_Fun> __fun, _Tuple&& __tupl) {
          {std::apply(__fun, (_Tuple&&) __tupl)} -> _P2300::__none_of<_P2300::__>;
        };
    template <class _Fun, class _Tuple>
        requires __applyable<_Fun, _Tuple>
      using __apply_result_t =
        decltype(std::apply(__applyable_fn<_Fun>{}, _P2300::__declval<_Tuple>()));

    template <class _T>
      using __decay_ref = std::decay_t<_T>&;

    template <class _Fun, class... _As>
      using __result_sender_t = std::decay_t<_P2300::__call_result_t<_Fun, __decay_ref<_As>...>>;

    template <class _Sender, class _Receiver, class _Fun, class _SetTag>
        requires std::execution::sender<_Sender, std::execution::env_of_t<_Receiver>>
      struct __storage {
        template <class... _As>
          struct __op_state_for_ {
            using __t =
              std::execution::connect_result_t<
                __result_sender_t<_Fun, _As...>,
                propagate_receiver_t<_P2300::__x<_Receiver>>>;
          };
        template <class... _As>
          using __op_state_for_t = _P2300::__t<__op_state_for_<_As...>>;

        // Compute a variant of tuples to hold all the values of the input
        // sender:
        using __args_t =
          _P2300::execution::__gather_sigs_t<_SetTag, _Sender, std::execution::env_of_t<_Receiver>, _P2300::__q<_P2300::execution::__decayed_tuple>, _P2300::execution::__nullable_variant_t>;

        // Compute a variant of operation states:
        using __op_state3_t =
          _P2300::execution::__gather_sigs_t<_SetTag, _Sender, std::execution::env_of_t<_Receiver>, _P2300::__q<__op_state_for_t>, _P2300::execution::__nullable_variant_t>;
        __op_state3_t __op_state3_;
      };

    template <class _Sender, class _Receiver, class _Fun, class _SetTag>
        requires std::execution::sender<_Sender, std::execution::env_of_t<_Receiver>>
      struct __max_sender_size {
        template <class... _As>
          struct __sender_size_for_ {
            using __t = _P2300::__index<sizeof(__result_sender_t<_Fun, _As...>)>;
          };
        template <class... _As>
          using __sender_size_for_t = _P2300::__t<__sender_size_for_<_As...>>;

        static constexpr std::size_t value =
          _P2300::__v<_P2300::execution::__gather_sigs_t<_SetTag, _Sender, std::execution::env_of_t<_Receiver>, _P2300::__q<__sender_size_for_t>, _P2300::__q<max_in_pack>>>;
      };

    template <class _Env, class _Fun, class _Set, class _Sig>
      struct __tfx_signal_impl {};

    template <class _Env, class _Fun, class _Set, class _Ret, class... _Args>
        requires (!std::same_as<_Set, _Ret>)
      struct __tfx_signal_impl<_Env, _Fun, _Set, _Ret(_Args...)> {
        using __t = std::execution::completion_signatures<_Ret(_Args...)>;
      };

    template <class _Env, class _Fun, class _Set, class... _Args>
        requires std::invocable<_Fun, __decay_ref<_Args>...> &&
          std::execution::sender<std::invoke_result_t<_Fun, __decay_ref<_Args>...>, _Env>
      struct __tfx_signal_impl<_Env, _Fun, _Set, _Set(_Args...)> {
        using __t =
          std::execution::make_completion_signatures<
            __result_sender_t<_Fun, _Args...>,
            _Env,
            // because we don't know if connect-ing the result sender will throw:
            std::execution::completion_signatures<std::execution::set_error_t(std::exception_ptr)>>;
      };

    template <class _SenderId, class _ReceiverId, class _FunId, class _Let>
      struct __operation;

    template <class _SenderId, class _ReceiverId, class _FunId, class _Let>
      struct __receiver : public receiver_base_t {
        using _Sender = _P2300::__t<_SenderId>;
        using _Receiver = _P2300::__t<_ReceiverId>;
        using _Fun = _P2300::__t<_FunId>;
        using _Env = std::execution::env_of_t<_Receiver>;

        constexpr static std::size_t memory_allocation_size = 
          _P2300::__v<__max_sender_size<_Sender, _Receiver, _Fun, _Let>>;

        template <class... _As>
          using __which_tuple_t =
            _P2300::__call_result_t<__which_tuple<_Sender, _Env, _Let>, _As...>;

        template <class... _As>
          using __op_state_for_t =
            _P2300::__minvoke2<_P2300::__q2<std::execution::connect_result_t>, __result_sender_t<_Fun, _As...>, propagate_receiver_t<_ReceiverId>>;

        // handle the case when let_error is used with an input sender that
        // never completes with set_error(exception_ptr)
        template <_P2300::__decays_to<std::exception_ptr> _Error>
            requires std::same_as<_Let, std::execution::set_error_t> &&
              (!_P2300::__v<_P2300::execution::__error_types_of_t<_Sender, _Env, _P2300::__transform<_P2300::__q1<std::decay_t>, _P2300::__contains<std::exception_ptr>>>>)
          friend void tag_invoke(std::execution::set_error_t, __receiver&& __self, _Error&& __err) noexcept {
            __self.__op_state_->propagate_completion_signal(std::execution::set_error, (_Error&&) __err);
          }

        template <_P2300::__one_of<_Let> _Tag, class... _As _NVCXX_CAPTURE_PACK(_As)>
            requires __applyable<_Fun, __which_tuple_t<_As...>&> &&
              std::execution::sender_to<__apply_result_t<_Fun, __which_tuple_t<_As...>&>, _Receiver>
          friend void tag_invoke(_Tag, __receiver&& __self, _As&&... __as) noexcept {
            _NVCXX_EXPAND_PACK(_As, __as,
              using __tuple_t = __which_tuple_t<_As...>;
              using __op_state_t = _P2300::__mapply<_P2300::__q<__op_state_for_t>, __tuple_t>;
              using result_sender_t = __result_sender_t<_Fun, _As...>;

              cudaStream_t stream = __self.__op_state_->stream_;

              result_sender_t* result_sender = reinterpret_cast<result_sender_t*>(__self.__op_state_->temp_storage_);
              kernel_with_result<<<1, 1, 0, stream>>>(__self.__op_state_->__fun_, result_sender, (_As&&)__as...);

              if (cudaError_t status = STDEXEC_DBG_ERR(cudaStreamSynchronize(stream)); status == cudaSuccess) {
                auto& __op = __self.__op_state_->__storage_.__op_state3_.template emplace<__op_state_t>(
                  _P2300::__conv{[&] {
                    return std::execution::connect(
                        *result_sender,
                        propagate_receiver_t<_ReceiverId>{
                          {},
                          static_cast<operation_state_base_t<_ReceiverId>&>(
                              *__self.__op_state_)});
                  }}
                );
                std::execution::start(__op);
              } else {
                __self.__op_state_->propagate_completion_signal(
                    std::execution::set_error, std::move(status));
              }
            )
          }

        template <_P2300::__one_of<std::execution::set_value_t, std::execution::set_error_t, std::execution::set_stopped_t> _Tag, class... _As _NVCXX_CAPTURE_PACK(_As)>
            requires _P2300::__none_of<_Tag, _Let> && _P2300::__callable<_Tag, _Receiver, _As...>
          friend void tag_invoke(_Tag __tag, __receiver&& __self, _As&&... __as) noexcept {
            _NVCXX_EXPAND_PACK(_As, __as,
              static_assert(_P2300::__nothrow_callable<_Tag, _Receiver, _As...>);
              __self.__op_state_->propagate_completion_signal(_Tag{}, (_As&&)__as...);
            )
          }

        friend auto tag_invoke(std::execution::get_env_t, const __receiver& __self)
          -> std::execution::env_of_t<_Receiver> {
          return std::execution::get_env(__self.__op_state_->receiver_);
        }

        __operation<_SenderId, _ReceiverId, _FunId, _Let>* __op_state_;
      };

    template <class _SenderId, class _ReceiverId, class _FunId, class _Let>
      using __operation_base =
        detail::operation_state_t<
          _SenderId,
          _P2300::__x<__receiver<_SenderId, _ReceiverId, _FunId, _Let>>,
          _ReceiverId>;

    template <class _SenderId, class _ReceiverId, class _FunId, class _Let>
      struct __operation : __operation_base<_SenderId, _ReceiverId, _FunId, _Let> {
        using _Sender = _P2300::__t<_SenderId>;
        using _Receiver = _P2300::__t<_ReceiverId>;
        using _Fun = _P2300::__t<_FunId>;
        using __receiver_t = __receiver<_SenderId, _ReceiverId, _FunId, _Let>;

        template <class _Receiver2>
          __operation(_Sender&& __sndr, _Receiver2&& __rcvr, _Fun __fun)
            : __operation_base<_SenderId, _ReceiverId, _FunId, _Let>(
                (_Sender&&) __sndr,
                std::execution::get_completion_scheduler<std::execution::set_value_t>(__sndr).hub_,
                (_Receiver2&&)__rcvr,
                [this] (operation_state_base_t<_P2300::__x<_Receiver2>> &) -> __receiver_t {
                  return __receiver_t{{}, this};
                })
            , __fun_((_Fun&&) __fun)
          {}
        _P2300_IMMOVABLE(__operation);

        _Fun __fun_;
        __storage<_Sender, _Receiver, _Fun, _Let> __storage_;
      };
  } // namespace let_xxx

  template <class _SenderId, class _FunId, class _SetId>
    struct let_sender_t : sender_base_t {
      using _Sender = _P2300::__t<_SenderId>;
      using _Fun = _P2300::__t<_FunId>;
      using _Set = _P2300::__t<_SetId>;
      template <class _Self, class _Receiver>
        using __operation_t =
          let_xxx::__operation<
            _P2300::__x<_P2300::__member_t<_Self, _Sender>>,
            _P2300::__x<std::remove_cvref_t<_Receiver>>,
            _FunId,
            _Set>;
      template <class _Self, class _Receiver>
        using __receiver_t =
          let_xxx::__receiver<
            _P2300::__x<_P2300::__member_t<_Self, _Sender>>,
            _P2300::__x<std::remove_cvref_t<_Receiver>>,
            _FunId,
            _Set>;

      template <class _Env, class _Sig>
        using __tfx_signal_t = _P2300::__t<let_xxx::__tfx_signal_impl<_Env, _Fun, _Set, _Sig>>;

      template <class _Env>
        using __tfx_signal = _P2300::__mbind_front_q1<__tfx_signal_t, _Env>;

      template <class _Sender, class _Env>
        using __with_error =
          _P2300::__if_c<
            _P2300::execution::__sends<_Set, _Sender, _Env>,
            _P2300::execution::completion_signatures<std::execution::set_error_t(cudaError_t)>,
            std::execution::completion_signatures<>>;

      template <class _Sender, class _Env>
        using __completions =
          _P2300::__mapply<
            _P2300::__transform<
              __tfx_signal<_Env>,
              _P2300::__mbind_front_q<_P2300::execution::__concat_completion_signatures_t, __with_error<_Sender, _Env>>>,
            std::execution::completion_signatures_of_t<_Sender, _Env>>;

      template <_P2300::__decays_to<let_sender_t> _Self, std::execution::receiver _Receiver>
          requires
            std::execution::sender_to<_P2300::__member_t<_Self, _Sender>, __receiver_t<_Self, _Receiver>>
        friend auto tag_invoke(std::execution::connect_t, _Self&& __self, _Receiver&& __rcvr)
          -> __operation_t<_Self, _Receiver> {
          return __operation_t<_Self, _Receiver>{
              ((_Self&&) __self).__sndr_,
              (_Receiver&&) __rcvr,
              ((_Self&&) __self).__fun_
          };
        }

      template <_P2300::execution::tag_category<std::execution::forwarding_sender_query> _Tag, class... _As _NVCXX_CAPTURE_PACK(_As)>
          requires _P2300::__callable<_Tag, const _Sender&, _As...>
        friend auto tag_invoke(_Tag __tag, const let_sender_t& __self, _As&&... __as)
          noexcept(_P2300::__nothrow_callable<_Tag, const _Sender&, _As...>)
          -> _P2300::execution::__call_result_if_t<_P2300::execution::tag_category<_Tag, std::execution::forwarding_sender_query>, _Tag, const _Sender&, _As...> {
          _NVCXX_EXPAND_PACK_RETURN(_As, __as,
            return ((_Tag&&) __tag)(__self.__sndr_, (_As&&) __as...);
          )
        }

      template <_P2300::__decays_to<let_sender_t> _Self, class _Env>
        friend auto tag_invoke(std::execution::get_completion_signatures_t, _Self&&, _Env)
          -> std::execution::dependent_completion_signatures<_Env>;
      template <_P2300::__decays_to<let_sender_t> _Self, class _Env>
        friend auto tag_invoke(std::execution::get_completion_signatures_t, _Self&&, _Env)
          -> __completions<_P2300::__member_t<_Self, _Sender>, _Env> requires true;

      _Sender __sndr_;
      _Fun __fun_;
    };
}

